import Foundation
import Observation
import os

@MainActor
@Observable
final class GlucoseStore {
    var readings: [GlucoseReading] = []
    var lastFetch: Date?
    var lastError: String?
    var isLoading: Bool = false
    var region: DexcomRegion {
        didSet { Task { await client.setRegion(region); UserDefaults.standard.set(region.rawValue, forKey: "region") } }
    }
    var pollMinutes: Int {
        didSet { UserDefaults.standard.set(pollMinutes, forKey: "pollMinutes") }
    }
    var hasCredentials: Bool
    var accountName: String

    let client: DexcomShareClient
    private var pollTask: Task<Void, Never>?
    private let log = Logger(subsystem: "se.kalasjocke.glucose", category: "Store")

    init() {
        let savedRegion = (UserDefaults.standard.string(forKey: "region")
            .flatMap(DexcomRegion.init(rawValue:))) ?? .ous
        // One-time migration: an earlier build defaulted to 5-minute polling.
        let migrationKey = "didMigrateTo1MinPollV1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            UserDefaults.standard.removeObject(forKey: "pollMinutes")
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        let savedPoll = UserDefaults.standard.object(forKey: "pollMinutes") as? Int ?? 1
        let creds = KeychainStore.read()
        self.region = savedRegion
        self.pollMinutes = savedPoll
        self.hasCredentials = creds != nil
        self.accountName = creds?.account ?? ""
        self.client = DexcomShareClient(region: savedRegion, credentials: creds)
    }

    var latestReading: GlucoseReading? { readings.last }

    var isStale: Bool {
        guard let last = readings.last else { return true }
        return Date().timeIntervalSince(last.date) > 15 * 60
    }

    /// Seconds since the last reading after which we expect a new one to be
    /// imminent. Dexcom samples every 5 minutes (300s); we open the "due"
    /// window 30 seconds early to absorb upload jitter on the Share side.
    private static let dueWindowAgeSeconds: TimeInterval = 270
    /// Aggressive polling cadence used while inside the due window.
    private static let aggressivePollSeconds: TimeInterval = 15

    func start() {
        guard hasCredentials else { return }
        stop()
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.fetchOnce()
                let interval = await MainActor.run { self.nextPollInterval() }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Pick the next poll interval: regular `pollMinutes` cadence normally,
    /// switching to a 15-second cadence once the latest reading is old enough
    /// that a new one is "due" from Dexcom.
    private func nextPollInterval() -> TimeInterval {
        let defaultInterval = Double(pollMinutes) * 60
        guard let latest = readings.last else { return defaultInterval }
        let age = Date().timeIntervalSince(latest.date)
        return age >= Self.dueWindowAgeSeconds ? Self.aggressivePollSeconds : defaultInterval
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func updateCredentials(account: String, password: String) async {
        KeychainStore.save(account: account, password: password)
        let creds = KeychainStore.Credentials(account: account, password: password)
        await client.setCredentials(creds)
        hasCredentials = true
        accountName = account
        await fetchOnce()
        start()
    }

    func clearCredentials() {
        KeychainStore.clear()
        Task { await client.setCredentials(nil) }
        hasCredentials = false
        accountName = ""
        readings = []
        lastFetch = nil
        stop()
    }

    func testConnection() async -> Result<Void, Error> {
        do {
            try await client.authenticate()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func fetchOnce() async {
        guard hasCredentials else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let newReadings = try await client.latestReadings()
            self.readings = newReadings
            self.lastFetch = Date()
            self.lastError = nil
            log.info("Fetched \(newReadings.count) readings")
        } catch {
            self.lastError = error.localizedDescription
            log.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func readings(in range: TimeRange) -> [GlucoseReading] {
        let cutoff = Date().addingTimeInterval(-Double(range.minutes) * 60)
        return readings.filter { $0.date >= cutoff }
    }
}
