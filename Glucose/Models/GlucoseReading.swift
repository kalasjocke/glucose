import Foundation

struct GlucoseReading: Identifiable, Hashable, Sendable {
    let date: Date
    let mmol: Double
    let trend: TrendDirection

    var id: Date { date }

    static let mgdlPerMmol = 18.0182

    init(date: Date, mmol: Double, trend: TrendDirection) {
        self.date = date
        self.mmol = mmol
        self.trend = trend
    }

    init(date: Date, mgdl: Double, trend: TrendDirection) {
        self.date = date
        self.mmol = mgdl / Self.mgdlPerMmol
        self.trend = trend
    }
}

enum GlucoseRange {
    static let lowMmol: Double = 3.9
    static let highMmol: Double = 10.0
}

extension Array where Element == GlucoseReading {
    /// Dexcom-style ±3 mg/dL/min cap, expressed in mmol/L/min.
    static var trendMaxSlope: Double { 0.167 }

    /// Slope in mmol/L per minute over the 3 readings ending at `reading`.
    /// Returns nil if fewer than 3 readings precede it (inclusive) or the
    /// timestamps are degenerate.
    func trendSlope(endingAt reading: GlucoseReading) -> Double? {
        guard let idx = firstIndex(where: { $0.id == reading.id }), idx >= 2 else { return nil }
        let newest = self[idx]
        let oldest = self[idx - 2]
        let dtMinutes = newest.date.timeIntervalSince(oldest.date) / 60.0
        guard dtMinutes > 0 else { return nil }
        return (newest.mmol - oldest.mmol) / dtMinutes
    }

    /// Arrow rotation in degrees, mapping slope to [-90°, +90°].
    /// 0° = flat (right), -90° = rising fast (up), +90° = falling fast (down).
    func trendAngleDegrees(endingAt reading: GlucoseReading) -> Double? {
        guard let slope = trendSlope(endingAt: reading) else { return nil }
        let ratio = Swift.max(-1.0, Swift.min(1.0, slope / Self.trendMaxSlope))
        return -ratio * 90.0
    }
}
