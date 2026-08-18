import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Query private var inventory: [InventoryItem]

    @State private var apiKeyInput = ""
    @State private var showingKeyField = false
    @State private var keySource = APIKeyStore.sourceDescription
    @State private var hasKey = APIKeyStore.hasKey

    @State private var notificationsEnabled = NotificationScheduler.isEnabled
    @State private var leadDays = NotificationScheduler.leadDays
    @State private var notifyHour = NotificationScheduler.hour
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount = 0

    @State private var modelSelections: [ClaudeTask: ClaudeModel] = [:]
    @State private var usageTotal = UsageTracker.shared.totalUSD
    @State private var usageCalls = UsageTracker.shared.callCount

    var body: some View {
        NavigationStack {
            Form {
                apiKeySection
                modelsSection
                notificationsSection
                usageSection
                maintenanceSection
                aboutSection
            }
            .navigationTitle("Settings")
            .task {
                loadModelSelections()
                await refreshNotificationState()
            }
        }
    }

    // MARK: - API key

    private var apiKeySection: some View {
        Section {
            HStack {
                Label("API key", systemImage: "key.fill")
                Spacer()
                Text(hasKey ? keySource : "Not set")
                    .foregroundStyle(hasKey ? Color.secondary : Color.orange)
            }

            if showingKeyField {
                SecureField("sk-ant-…", text: $apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Button("Save key") {
                        APIKeyStore.save(apiKeyInput)
                        apiKeyInput = ""
                        showingKeyField = false
                        refreshKeyState()
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                    Spacer()

                    Button("Cancel") {
                        apiKeyInput = ""
                        showingKeyField = false
                    }
                    .foregroundStyle(.secondary)
                }
            } else {
                Button(hasKey ? "Replace key" : "Add key") { showingKeyField = true }
                if hasKey {
                    Button("Remove key", role: .destructive) {
                        APIKeyStore.clear()
                        refreshKeyState()
                    }
                }
            }
        } header: {
            Text("Anthropic")
        } footer: {
            Text("Used for photo recognition, shelf-life estimates, and recipe extraction. Stored in the device keychain. Everything else in Pantry stays on this device — there's no backend and no sync.")
        }
    }

    // MARK: - Models

    private var modelsSection: some View {
        Section {
            ForEach(ClaudeTask.allCases) { task in
                let selected = model(for: task)
                NavigationLink {
                    ModelPickerView(task: task) { newModel in
                        modelSelections[task] = newModel
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.displayName)
                            if selected != task.recommended {
                                Text("changed from recommended")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(selected.displayName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button("Reset all to recommended") {
                ModelPreferences.resetAll()
                loadModelSelections()
            }
            .disabled(usingAllRecommendations)
        } header: {
            Text("Models")
        } footer: {
            Text("Each job picks its own model, because they aren't the same difficulty. Reading a shelf-life fact is not the same problem as untangling a recipe from an Instagram caption.")
        }
    }

    private func model(for task: ClaudeTask) -> ClaudeModel {
        modelSelections[task] ?? ModelPreferences.model(for: task)
    }

    private var usingAllRecommendations: Bool {
        ClaudeTask.allCases.allSatisfy { model(for: $0) == $0.recommended }
    }

    private func loadModelSelections() {
        modelSelections = Dictionary(
            uniqueKeysWithValues: ClaudeTask.allCases.map { ($0, ModelPreferences.model(for: $0)) }
        )
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Toggle("Remind me before food expires", isOn: $notificationsEnabled)
                .onChange(of: notificationsEnabled) { _, newValue in
                    NotificationScheduler.isEnabled = newValue
                    Task {
                        if newValue { await NotificationScheduler.requestAuthorization() }
                        await refreshNotificationState()
                    }
                }

            if notificationsEnabled {
                Picker("Warn me", selection: $leadDays) {
                    Text("On the day").tag(0)
                    Text("1 day before").tag(1)
                    Text("2 days before").tag(2)
                    Text("3 days before").tag(3)
                    Text("A week before").tag(7)
                }
                .onChange(of: leadDays) { _, newValue in
                    NotificationScheduler.leadDays = newValue
                    Task { await refreshNotificationState() }
                }

                Picker("At", selection: $notifyHour) {
                    ForEach([7, 8, 9, 10, 12, 17, 18, 19], id: \.self) { hour in
                        Text(hourLabel(hour)).tag(hour)
                    }
                }
                .onChange(of: notifyHour) { _, newValue in
                    NotificationScheduler.hour = newValue
                    Task { await refreshNotificationState() }
                }

                if authStatus == .denied {
                    Label(
                        "Notifications are turned off for Pantry in iOS Settings.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(notificationsEnabled
                 ? "\(pendingCount) reminder\(pendingCount == 1 ? "" : "s") scheduled. Items expiring on the same day are grouped into one."
                 : "The Inventory tab still shows a \"use soon\" list either way.")
        }
    }

    // MARK: - Usage

    private var usageSection: some View {
        Section {
            LabeledContent("API calls made", value: "\(usageCalls)")
            LabeledContent("Estimated spend", value: usageTotal.formatted(.currency(code: "USD")))
            Button("Reset counter") {
                UsageTracker.shared.reset()
                usageTotal = 0
                usageCalls = 0
            }
        } header: {
            Text("Claude usage")
        } footer: {
            Text("A rough local tally, priced at each model's list rate as calls are made. Check the Anthropic console for what you were actually billed.")
        }
    }

    private var maintenanceSection: some View {
        Section {
            Button("Clear saved shelf-life estimates") {
                ShelfLifeEstimator.clearCache()
            }
        } header: {
            Text("Maintenance")
        } footer: {
            Text("Estimates Claude has given for unusual items are cached so the same item isn't looked up twice. Clear this if an estimate looked wrong.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Items tracked", value: "\(inventory.count)")
            Text("Instagram import reads a reel's caption and cover image. Private reels, and recipes only spoken aloud in the video, won't come through — paste the caption in manually when that happens.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func refreshKeyState() {
        hasKey = APIKeyStore.hasKey
        keySource = APIKeyStore.sourceDescription
    }

    private func refreshNotificationState() async {
        authStatus = await NotificationScheduler.authorizationStatus()
        await NotificationScheduler.reschedule(for: inventory)
        pendingCount = await NotificationScheduler.pendingCount()
    }
}
