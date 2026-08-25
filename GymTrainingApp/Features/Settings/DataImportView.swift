import SwiftUI
import UniformTypeIdentifiers

struct DataImportView: View {
    @EnvironmentObject private var appStore: AppStore

    @State private var isSelectingFile = false
    @State private var selectedFile: SelectedImportFile?
    @State private var preview: DataImportPreview?
    @State private var options = DataImportOptions()
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isConfirmingRestore = false
    @State private var isConfirmingRollback = false

    var body: some View {
        List {
            Section {
                Button {
                    isSelectingFile = true
                } label: {
                    Label("ファイルを選ぶ", systemImage: "doc.badge.plus")
                        .font(.body.weight(.semibold))
                }
                .accessibilityIdentifier("selectImportFileButton")

                if let preview {
                    LabeledContent("形式", value: preview.format.displayName)
                    LabeledContent("ファイル", value: preview.fileName)
                }
            } header: {
                Text("記録を取り込む")
            } footer: {
                Text("BodyMode、Strong、Hevy、JEFIT、Apple Health、一般的なCSVに対応します。取り込み前に内容を確認でき、直前の取り込みは一括で元に戻せます。")
            }

            if let preview {
                previewSection(preview)
                importRequirementsSection(preview)
                warningSection(preview)

                Section {
                    Button {
                        if preview.format == .bodyModeJSON {
                            isConfirmingRestore = true
                        } else {
                            applyImport(preview)
                        }
                    } label: {
                        Label(importButtonTitle(preview), systemImage: "tray.and.arrow.down.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .font(.body.weight(.bold))
                    }
                    .disabled(!preview.canImport)
                    .accessibilityIdentifier("applyDataImportButton")
                }
            }

            if let receipt = appStore.latestUndoableDataImport {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.fileName)
                            .font(.body.weight(.semibold))
                        Text("\(receipt.format.displayName)・\(receipt.summary.totalRecordCount)件")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    Button(role: .destructive) {
                        isConfirmingRollback = true
                    } label: {
                        Label("この取り込みを元に戻す", systemImage: "arrow.uturn.backward.circle")
                    }
                    .accessibilityIdentifier("rollbackDataImportButton")
                } header: {
                    Text("直前の取り込み")
                } footer: {
                    Text("取り込み前の記録へ戻します。その後に追加・編集した内容も戻るため、必要な場合は先にJSONを書き出してください。")
                }
            }

            if let successMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.positive)
                        .accessibilityIdentifier("dataImportSuccessMessage")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle("データ取り込み")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isSelectingFile,
            allowedContentTypes: [.json, .commaSeparatedText, .xml, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .confirmationDialog(
            "現在のBodyModeデータを置き換えますか？",
            isPresented: $isConfirmingRestore,
            titleVisibility: .visible
        ) {
            Button("バックアップから復元", role: .destructive) {
                if let preview { applyImport(preview) }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("復元前の状態は自動保存され、この画面から一括で元に戻せます。")
        }
        .confirmationDialog(
            "直前の取り込みを元に戻しますか？",
            isPresented: $isConfirmingRollback,
            titleVisibility: .visible
        ) {
            Button("取り込み前へ戻す", role: .destructive) {
                rollbackImport()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("取り込みできません", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "不明なエラー")
        }
    }

    @ViewBuilder
    private func previewSection(_ preview: DataImportPreview) -> some View {
        Section("追加される内容") {
            if preview.summary.workoutCount > 0 {
                countRow("ワークアウト", count: preview.summary.workoutCount, systemImage: "dumbbell.fill")
            }
            if preview.summary.exerciseCount > 0 {
                countRow("種目", count: preview.summary.exerciseCount, systemImage: "figure.strengthtraining.traditional")
            }
            if preview.summary.setCount > 0 {
                countRow("セット", count: preview.summary.setCount, systemImage: "list.number")
            }
            if preview.summary.bodyMetricCount > 0 {
                countRow("身体記録", count: preview.summary.bodyMetricCount, systemImage: "scalemass")
            }
            if preview.summary.planCount > 0 {
                countRow("計画", count: preview.summary.planCount, systemImage: "list.clipboard")
            }
            if preview.summary.mealCount > 0 {
                countRow("食事", count: preview.summary.mealCount, systemImage: "fork.knife")
            }
            if preview.summary.photoCount > 0 {
                countRow("体型写真", count: preview.summary.photoCount, systemImage: "photo.on.rectangle")
            }
            if preview.summary.duplicateCount > 0 {
                LabeledContent {
                    Text("\(preview.summary.duplicateCount)件")
                } label: {
                    Label("重複のため除外", systemImage: "doc.on.doc")
                }
            }
            if preview.format == .bodyModeJSON {
                Label("プロフィールやAI提案履歴を含むバックアップ全体", systemImage: "externaldrive.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
    }

    @ViewBuilder
    private func importRequirementsSection(_ preview: DataImportPreview) -> some View {
        if preview.requiresWeightUnit || preview.requiresTimeZoneConfirmation {
            Section("読み込み設定") {
                if preview.requiresWeightUnit {
                    Picker("CSVの重量単位", selection: $options.ambiguousWeightUnit) {
                        Text("選択してください").tag(WeightUnit?.none)
                        Text("kg").tag(WeightUnit?.some(.kg))
                        Text("lb").tag(WeightUnit?.some(.lb))
                    }
                    .onChange(of: options.ambiguousWeightUnit) { _, _ in refreshPreview() }
                    .accessibilityIdentifier("importWeightUnitPicker")
                }
                if preview.requiresTimeZoneConfirmation {
                    LabeledContent("日時のタイムゾーン", value: options.timeZone.identifier)
                    Toggle("このタイムゾーンで読み込む", isOn: $options.hasConfirmedTimeZone)
                        .onChange(of: options.hasConfirmedTimeZone) { _, _ in refreshPreview() }
                        .accessibilityIdentifier("confirmImportTimeZoneToggle")
                }
            }
        }
    }

    @ViewBuilder
    private func warningSection(_ preview: DataImportPreview) -> some View {
        if !preview.warnings.isEmpty {
            Section("確認事項") {
                ForEach(preview.warnings) { warning in
                    Label {
                        Text(warning.message)
                            .font(.footnote)
                    } icon: {
                        Image(systemName: warningIcon(warning.severity))
                            .foregroundStyle(warningColor(warning.severity))
                    }
                }
            }
        }
    }

    private func countRow(_ title: String, count: Int, systemImage: String) -> some View {
        LabeledContent {
            Text("\(count)件")
                .font(.body.monospacedDigit())
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func importButtonTitle(_ preview: DataImportPreview) -> String {
        if preview.format == .bodyModeJSON { return "このバックアップから復元" }
        return "\(preview.summary.totalRecordCount)件を取り込む"
    }

    private func warningIcon(_ severity: DataImportWarningSeverity) -> String {
        switch severity {
        case .information: "info.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .blocking: "xmark.octagon.fill"
        }
    }

    private func warningColor(_ severity: DataImportWarningSeverity) -> Color {
        switch severity {
        case .information: AppTheme.accent
        case .caution: AppTheme.warning
        case .blocking: .red
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let file = SelectedImportFile(name: url.lastPathComponent, data: try Data(contentsOf: url))
            selectedFile = file
            options = DataImportOptions()
            successMessage = nil
            preview = try appStore.prepareDataImport(data: file.data, fileName: file.name, options: options)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshPreview() {
        guard let selectedFile else { return }
        do {
            preview = try appStore.prepareDataImport(
                data: selectedFile.data,
                fileName: selectedFile.name,
                options: options
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyImport(_ preview: DataImportPreview) {
        do {
            let receipt = try appStore.applyDataImport(preview)
            successMessage = "\(receipt.fileName)を取り込みました。"
            selectedFile = nil
            self.preview = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rollbackImport() {
        do {
            let receipt = try appStore.rollbackLatestDataImport()
            successMessage = "\(receipt.fileName)の取り込みを元に戻しました。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SelectedImportFile {
    var name: String
    var data: Data
}
