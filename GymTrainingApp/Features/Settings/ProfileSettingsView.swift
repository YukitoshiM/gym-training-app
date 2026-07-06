import SwiftUI

struct ProfileSettingsView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: UserProfile
    @State private var heightText: String
    @State private var birthYearText: String
    @State private var isConfirmingReset = false

    init(profile: UserProfile) {
        _draft = State(initialValue: profile)
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
        dismiss()
    }
}

#Preview {
    ProfileSettingsView(profile: .default)
        .environmentObject(AppStore())
}
