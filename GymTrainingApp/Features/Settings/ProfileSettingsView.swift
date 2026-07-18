import SwiftUI

struct ProfileSettingsView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager
    @EnvironmentObject private var gymLocationManager: GymLocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var draft: UserProfile
    @State private var aiDraft: AISettings
    @State private var sensorDraft: SensorSettings
    @State private var heightText: String
    @State private var birthYearText: String
    @State private var isConfirmingReset = false
    @State private var isCheckingAI = false
    @State private var aiConnectionResult: AIConnectionCheckResult?
    @State private var isExportingData = false
    @State private var exportDocument = GymDataExportDocument()
    @State private var exportErrorMessage: String?
    @State private var isAISharingExpanded = false

    init(
        profile: UserProfile,
        aiSettings: AISettings = .default,
        sensorSettings: SensorSettings = .default
    ) {
        _draft = State(initialValue: profile)
        _aiDraft = State(initialValue: aiSettings)
        _sensorDraft = State(initialValue: sensorSettings)
        _heightText = State(initialValue: profile.heightCm.map { String(format: "%.1f", $0) } ?? "")
        _birthYearText = State(initialValue: profile.birthYear.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("プロフィール") {
                    Picker("目的", selection: $draft.goalType) {
                        ForEach(GoalType.allCases) { goal in
                            Text(goal.displayName).tag(goal)
                        }
                    }

                    NumericTextInputControl(
                        text: $heightText,
                        title: "身長",
                        unit: "cm",
                        range: 50...250,
                        step: 0.1,
                        defaultValue: 170,
                        accessibilityIdentifier: "profileHeightField"
                    )

                    NumericTextInputControl(
                        text: $birthYearText,
                        title: "生年",
                        unit: "年",
                        range: 1900...Double(Calendar.current.component(.year, from: Date())),
                        step: 1,
                        defaultValue: Double(Calendar.current.component(.year, from: Date()) - 30),
                        accessibilityIdentifier: "profileBirthYearField"
                    )

                    Picker("性別", selection: $draft.sex) {
                        ForEach(Sex.allCases) { sex in
                            Text(sex.displayName).tag(sex)
                        }
                    }

                    Picker("経験レベル", selection: $draft.experienceLevel) {
                        ForEach(ExperienceLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                }

                Section("表示") {
                    Picker("重量単位", selection: $draft.weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Apple Healthワークアウト", isOn: $sensorDraft.healthIntegrationEnabled)
                        .disabled(healthDataManager.accessState == .unavailable)
                    Toggle("Watchで動作回数を推定", isOn: $sensorDraft.motionRepDetectionEnabled)
                    Toggle("心拍とRPEで休憩を調整", isOn: $sensorDraft.adaptiveRestEnabled)
                    Toggle("Watchの触覚通知", isOn: $sensorDraft.hapticCoachingEnabled)
                    Toggle("省電力サンプリング", isOn: $sensorDraft.reducedSensorSamplingEnabled)
                    Toggle("ジム訪問を自動記録", isOn: $sensorDraft.gymVisitDetectionEnabled)

                    Button {
                        Task { await healthDataManager.requestAuthorization() }
                    } label: {
                        Label("Healthの共有項目を確認", systemImage: "heart.text.square")
                    }
                    .disabled(!sensorDraft.healthIntegrationEnabled)
                    .accessibilityIdentifier("requestHealthFromSettingsButton")
                } header: {
                    Text("Apple Watch・センサー")
                } footer: {
                    Text("センサーが使えない場合も、重量・回数・RPEは手入力で記録できます。省電力サンプリングでは動作推定の更新頻度を下げます。")
                }

                Section {
                    Toggle("AI機能を使う", isOn: $aiDraft.isEnabled)

                    DisclosureGroup("AIへ送るデータ", isExpanded: $isAISharingExpanded) {
                        Toggle("身体KPI", isOn: $aiDraft.dataSharing.bodyMetrics)
                        Toggle("食事", isOn: $aiDraft.dataSharing.meals)
                        Toggle("筋トレ", isOn: $aiDraft.dataSharing.workouts)
                        Toggle("体型写真", isOn: $aiDraft.dataSharing.bodyPhotos)
                        Toggle("睡眠・回復", isOn: $aiDraft.dataSharing.sleepAndRecovery)
                        Toggle("日常活動", isOn: $aiDraft.dataSharing.dailyActivity)
                        Toggle("ジム訪問", isOn: $aiDraft.dataSharing.gymVisits)
                        Toggle("心拍・モーション", isOn: $aiDraft.dataSharing.workoutSensors)
                    }
                    .disabled(!aiDraft.isEnabled)

                    Text("現在選択: \(aiDraft.dataSharing.enabledCategoryNames.joined(separator: "、").ifEmpty("なし"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("サーバーURL", text: $aiDraft.baseURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .accessibilityIdentifier("aiBaseURLField")

                    SecureField("APIキー", text: $aiDraft.apiKey)
                        .textInputAutocapitalization(.never)

                    Button {
                        aiDraft.baseURLString = AISettings.default.baseURLString
                        aiDraft.apiKey = AISettings.default.apiKey
                        aiConnectionResult = nil
                    } label: {
                        Label("Simulator推奨値に戻す", systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityIdentifier("resetAISettingsToSimulatorButton")

                    Button {
                        checkAIHealth()
                    } label: {
                        Label(isCheckingAI ? "確認中" : "接続確認", systemImage: "network")
                    }
                    .disabled(isCheckingAI || !aiDraft.isEnabled)
                    .accessibilityIdentifier("checkAIHealthButton")

                    if let aiConnectionResult {
                        AIConnectionCheckCard(result: aiConnectionResult)
                    }
                } header: {
                    Text("ローカルLLM")
                } footer: {
                    Text("Simulatorなら http://127.0.0.1:8765。実機はMacのLAN IPまたはTailscale名を使います。接続確認はAPI、Ollama、モデル取得状態まで確認します。")
                }

                Section("データ") {
                    Button {
                        prepareExport()
                    } label: {
                        Label("全記録をJSONで書き出す", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportAllDataButton")

                    Button(role: .destructive) {
                        isConfirmingReset = true
                    } label: {
                        Label("全データ削除", systemImage: "trash")
                    }
                    .accessibilityIdentifier("resetAllDataButton")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        save()
                    }
                    .accessibilityIdentifier("saveProfileSettingsButton")
                }
            }
            .confirmationDialog("全データを削除しますか？", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button("全データ削除", role: .destructive) {
                    appStore.resetAllData()
                    dismiss()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("計画、履歴、身体KPI、食事、写真、カスタム種目を削除します。")
            }
            .fileExporter(
                isPresented: $isExportingData,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "gym-training-export"
            ) { result in
                if case .failure(let error) = result {
                    exportErrorMessage = error.localizedDescription
                }
            }
            .alert("書き出せませんでした", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "不明なエラー")
            }
        }
    }

    private func save() {
        draft.heightCm = Double(heightText)
        draft.birthYear = Int(birthYearText)
        appStore.saveUserProfile(draft)
        if healthDataManager.accessState == .unavailable {
            sensorDraft.healthIntegrationEnabled = false
        }
        sensorDraft.includeSensorDataInAI = aiDraft.dataSharing.sleepAndRecovery
            || aiDraft.dataSharing.dailyActivity
            || aiDraft.dataSharing.gymVisits
            || aiDraft.dataSharing.workoutSensors
        appStore.saveAISettings(aiDraft)
        appStore.saveSensorSettings(sensorDraft)
        if sensorDraft.gymVisitDetectionEnabled {
            gymLocationManager.enableBackgroundVisitDetection()
        } else {
            gymLocationManager.disableVisitDetection()
        }
        dismiss()
    }

    private func checkAIHealth() {
        guard aiDraft.isEnabled else {
            aiConnectionResult = .disabled
            return
        }

        isCheckingAI = true
        aiConnectionResult = nil

        Task {
            do {
                let health = try await LocalAIClient(settings: aiDraft).health()
                await MainActor.run {
                    aiConnectionResult = .init(health: health)
                    isCheckingAI = false
                }
            } catch {
                await MainActor.run {
                    aiConnectionResult = .init(error: error)
                    isCheckingAI = false
                }
            }
        }
    }

    private func prepareExport() {
        do {
            exportDocument = GymDataExportDocument(data: try appStore.makeExportData())
            isExportingData = true
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

private struct AIConnectionCheckResult {
    enum Level {
        case ready
        case warning
        case failure
    }

    var level: Level
    var title: String
    var detail: String
    var recovery: String?

    static let disabled = AIConnectionCheckResult(
        level: .warning,
        title: "AI機能はオフです",
        detail: "手動記録はこのまま使えます。",
        recovery: "AI下書きや週次コメントを使う場合は、AI機能をオンにしてから接続確認してください。"
    )

    init(level: Level, title: String, detail: String, recovery: String?) {
        self.level = level
        self.title = title
        self.detail = detail
        self.recovery = recovery
    }

    init(health: AIHealthResponse) {
        if health.isReady {
            self.init(
                level: .ready,
                title: "ローカルLLM接続OK",
                detail: "APIサーバーとOllama \(health.model) に接続できています。",
                recovery: health.message
            )
        } else if !health.ollamaReachable {
            self.init(
                level: .warning,
                title: "APIは起動中 / Ollama未接続",
                detail: "local_llm_server は応答していますが、Ollamaに届いていません。",
                recovery: health.message ?? "Mac miniで `ollama serve` を起動してから、もう一度接続確認してください。"
            )
        } else {
            self.init(
                level: .warning,
                title: "Ollamaモデルが未取得です",
                detail: "Ollamaは起動していますが、設定中のモデル \(health.model) が見つかりません。",
                recovery: health.message ?? "Mac miniで `ollama pull \(health.model)` を実行するか、local_llm_server の OLLAMA_MODEL を変更してください。"
            )
        }
    }

    init(error: Error) {
        let presentation = AIClientError.presentation(for: error)
        self.init(
            level: .failure,
            title: presentation.message,
            detail: "AI下書きや週次コメントは実行できませんが、手動記録は保存できます。",
            recovery: presentation.recovery
        )
    }

    var tint: Color {
        switch level {
        case .ready: .green
        case .warning: AppTheme.orange
        case .failure: .red
        }
    }

    var systemImage: String {
        switch level {
        case .ready: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }
}

private struct AIConnectionCheckCard: View {
    let result: AIConnectionCheckResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(result.title, systemImage: result.systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(result.tint)

            Text(result.detail)
                .font(.caption)
                .foregroundStyle(AppTheme.ink)

            if let recovery = result.recovery, !recovery.isEmpty {
                Text(recovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("aiConnectionResultCard")
    }
}

#Preview {
    ProfileSettingsView(profile: .default, aiSettings: .default)
        .environmentObject(AppStore())
        .environmentObject(HealthDataManager())
        .environmentObject(GymLocationManager())
}
