import SwiftUI

struct SettingsView: View {
    @Environment(GlucoseStore.self) private var store
    @State private var account: String = ""
    @State private var password: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var saved: Bool = false

    enum TestStatus: Equatable {
        case idle
        case running
        case success
        case failure(String)
    }

    var body: some View {
        @Bindable var bindableStore = store
        Form {
            Section("Dexcom Share") {
                TextField("Username", text: $account)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
                Picker("Region", selection: $bindableStore.region) {
                    ForEach(DexcomRegion.allCases) { r in
                        Text(r.label).tag(r)
                    }
                }
                HStack {
                    Button("Save & Connect") { saveAndConnect() }
                        .keyboardShortcut(.return)
                        .disabled(account.isEmpty || password.isEmpty)
                    Button("Test connection") { test() }
                        .disabled(account.isEmpty || password.isEmpty || testStatus == .running)
                    Spacer()
                    statusLabel
                }
                if store.hasCredentials {
                    Button("Sign out", role: .destructive) {
                        store.clearCredentials()
                        account = ""
                        password = ""
                        saved = false
                    }
                }
            }
            Section("Updates") {
                Picker("Poll interval", selection: $bindableStore.pollMinutes) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                }
                if let last = store.lastFetch {
                    LabeledContent("Last fetch") {
                        Text(last, format: .dateTime.hour().minute().second())
                    }
                }
                if let err = store.lastError {
                    LabeledContent("Last error") {
                        Text(err).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 480, height: 380)
        .onAppear {
            account = store.accountName
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch testStatus {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .success:
            Label("OK", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private func test() {
        let acc = account
        let pwd = password
        testStatus = .running
        Task {
            await store.client.setCredentials(.init(account: acc, password: pwd))
            let result = await store.testConnection()
            await MainActor.run {
                switch result {
                case .success:
                    testStatus = .success
                case .failure(let err):
                    testStatus = .failure(err.localizedDescription)
                }
            }
        }
    }

    private func saveAndConnect() {
        let acc = account
        let pwd = password
        Task {
            await store.updateCredentials(account: acc, password: pwd)
            await MainActor.run { saved = true; testStatus = .success }
        }
    }
}
