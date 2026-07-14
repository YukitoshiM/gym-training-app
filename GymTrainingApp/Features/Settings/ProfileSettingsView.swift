import SwiftUI

struct ProfileSettingsView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: UserProfile
    @State private var aiDraft: AISettings
    @State private var heightText: String
    @State private var birthYearText: String
    @State private var isConfirmingReset = false
    @State private var isCheckingAI = false
    @State private var aiConnectionResult: AIConnectionCheckResult?

    init(profile: UserProfile, aiSettings: AISettings = .default) {
        _draft = State(initialValue: profile)
        _aiDraft = State(initialValue: aiSettings)
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

                    TextField("身長 cm", text: $heightText)
                        .keyboardType(.decimalPad)

                    TextField("生年", text: $birthYearText)
                        .keyboardType(.numberPad)

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
                    Toggle("AI機能を使う", isOn: $aiDraft.isEnabled)

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
        }
    }

    private func save() {
        draft.heightCm = Double(heightText)
        draft.birthYear = Int(birthYearText)
        appStore.saveUserProfile(draft)
        appStore.saveAISettings(aiDraft)
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
}
