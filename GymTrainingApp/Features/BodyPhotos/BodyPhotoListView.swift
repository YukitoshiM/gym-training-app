import AVFoundation
import PhotosUI
import SwiftUI

struct BodyPhotoListView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var editorRequest: BodyPhotoEditorRequest?
    @State private var didPresentInitialEditor = false
    private let startsWithEditor: Bool

    init(startsWithEditor: Bool = false) {
        self.startsWithEditor = startsWithEditor
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        MetricPill(
                            title: L10n.string("health_meals_body_ai.452d17cd1b90", fallback: "今日のセット"),
                            value: appStore.bodyPhotoSet() == nil ? "0" : "1",
                            systemImage: "camera",
                            tint: AppTheme.purple
                        )
                        MetricPill(
                            title: L10n.string("health_meals_body_ai.ec6849d2b62a", fallback: "撮影日数"),
                            value: "\(appStore.bodyPhotoSets.count)",
                            systemImage: "calendar",
                            tint: AppTheme.blue
                        )
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section(L10n.string("health_meals_body_ai.6920fd3d3872", fallback: "撮影セット")) {
                    if appStore.bodyPhotoSets.isEmpty {
                        ContentUnavailableView(
                            L10n.string("health_meals_body_ai.a45de1210f8a", fallback: "体型写真はまだありません"),
                            systemImage: "camera.viewfinder",
                            description: Text(L10n.string("health_meals_body_ai.84df3f0402ab", fallback: "正面・横・背面などを1日分のセットとして記録します。"))
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    ForEach(appStore.bodyPhotoSets) { set in
                        NavigationLink {
                            BodyPhotoSetDetailView(setDate: set.date)
                        } label: {
                            BodyPhotoSetRow(
                                set: set,
                                coachPersona: appStore.userProfile.coachPersona
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("bodyPhotoRow-\(set.entries.first?.angle.rawValue ?? "set")")
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: appStore.deleteBodyPhotoSets)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(TrainingBackground())
            .navigationTitle(L10n.string("health_meals_body_ai.f47d6f2e6ec3", fallback: "体型写真"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorRequest = BodyPhotoEditorRequest(set: appStore.bodyPhotoSet())
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(appStore.bodyPhotoSet() == nil ? L10n.string("health_meals_body_ai.4fcfec9e3704", fallback: "今日の撮影セットを追加") : L10n.string("health_meals_body_ai.0e1b8e6dc426", fallback: "今日の撮影セットを編集"))
                    .accessibilityIdentifier("addBodyPhotoButton")
                }
            }
            .sheet(item: $editorRequest) { request in
                BodyPhotoEditorView(existingSet: request.set) {
                    editorRequest = nil
                }
            }
            .onAppear {
                guard startsWithEditor, !didPresentInitialEditor else { return }
                didPresentInitialEditor = true
                editorRequest = BodyPhotoEditorRequest(set: appStore.bodyPhotoSet())
            }
        }
    }
}

private struct BodyPhotoEditorRequest: Identifiable {
    let id = UUID()
    let set: BodyPhotoSet?
}

private struct BodyPhotoSetRow: View {
    let set: BodyPhotoSet
    let coachPersona: CoachPersona

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(set.date.formatted(.dateTime.year().month().day()))
                            .font(.headline)
                        Text(L10n.string("health_meals_body_ai.8ed437093c0a", fallback: "{{value1}}枚の撮影セット", values: [String(describing: set.photoEntries.count)]))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    Spacer()

                    BodyPhotoAnalysisStatus(set: set)
                }

                if set.angleEntries.isEmpty {
                    Label(set.memo.isEmpty ? L10n.string("health_meals_body_ai.7b243ff0f863", fallback: "写真を追加") : set.memo, systemImage: "camera.viewfinder")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedInk)
                } else {
                    HStack(spacing: 8) {
                        ForEach(set.angleEntries.prefix(4)) { entry in
                            BodyPhotoThumbnail(entry: entry, size: 58)
                        }
                    }
                }

                if let summary = set.analysis?.summary {
                    HStack(alignment: .top, spacing: 7) {
                        CoachAvatarView(persona: coachPersona, size: 24, cornerRadius: 6)
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.accent)
                            .lineLimit(2)
                    }
                } else if !set.memo.isEmpty {
                    Text(set.memo)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }
}

private struct BodyPhotoAnalysisStatus: View {
    let set: BodyPhotoSet

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.bold())
            .foregroundStyle(set.needsAnalysis ? AppTheme.mutedInk : AppTheme.accent)
    }

    private var title: String {
        if set.photoEntries.isEmpty { return L10n.string("health_meals_body_ai.2071566e71be", fallback: "写真なし") }
        if set.needsAnalysis { return set.analysis == nil ? L10n.string("health_meals_body_ai.1583e5cb8444", fallback: "未分析") : L10n.string("health_meals_body_ai.8ac60e95bd23", fallback: "再分析が必要") }
        return L10n.string("health_meals_body_ai.0ef0d76a0e8d", fallback: "分析済み")
    }

    private var symbol: String {
        if set.photoEntries.isEmpty { return "photo.badge.plus" }
        if set.needsAnalysis { return "arrow.triangle.2.circlepath" }
        return "checkmark.circle.fill"
    }
}

private struct BodyPhotoSetDetailView: View {
    @EnvironmentObject private var appStore: AppStore
    let setDate: Date

    @State private var isEditing = false
    @State private var isAnalyzing = false
    @State private var aiError: AIErrorPresentation?
    @State private var creditAccessIssue: AICreditAccessIssue?

    private var set: BodyPhotoSet? {
        appStore.bodyPhotoSet(on: setDate)
    }

    var body: some View {
        ScrollView {
            if let set {
                VStack(alignment: .leading, spacing: 18) {
                    BodyPhotoSetOverview(set: set)

                    BodyPhotoMeasurementContextCard(date: set.date)

                    if let comment = set.analysis {
                        BodyPhotoAICommentCard(
                            comment: comment,
                            coachPersona: appStore.userProfile.coachPersona
                        )
                    } else {
                        CardContainer {
                            VStack(alignment: .leading, spacing: 8) {
                                CoachAttributionLabel(
                                    persona: appStore.userProfile.coachPersona,
                                    text: L10n.string("health_meals_body_ai.d94549194ed1", fallback: "{{value1}}がセット全体を確認", values: [String(describing: appStore.userProfile.coachPersona.displayName)])
                                )
                                Text(L10n.string("health_meals_body_ai.08aa1158cdcc", fallback: "複数方向の写真をまとめて送ると、正面だけでは分からない姿勢や体型を補い合って確認できます。"))
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                        }
                    }

                    if let aiError {
                        BodyPhotoAIErrorCard(error: aiError)
                    }

                    VStack(spacing: 10) {
                        AICreditCostStatusView(feature: "body_photo", settings: appStore.aiSettings)

                        Button {
                            analyze(set)
                        } label: {
                            Label(
                                isAnalyzing ? L10n.string("health_meals_body_ai.7c3d20b5d555", fallback: "分析中") : (set.analysis == nil ? L10n.string("health_meals_body_ai.b57fc7605da1", fallback: "このセットを分析") : L10n.string("health_meals_body_ai.d5b6606496a9", fallback: "写真をまとめて再分析")),
                                systemImage: "sparkles"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAnalyze(set) || isAnalyzing)
                        .accessibilityIdentifier("reanalyzeBodyPhotoSetButton")

                        Button {
                            isEditing = true
                        } label: {
                            Label(L10n.string("health_meals_body_ai.4cf77e9f289c", fallback: "写真を追加・編集"), systemImage: "photo.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("editBodyPhotoSetButton")
                    }
                }
                .padding()
            }
        }
        .background(TrainingBackground())
        .navigationTitle(setDate.formatted(.dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditing) {
            if let set {
                BodyPhotoEditorView(existingSet: set) {
                    isEditing = false
                }
            }
        }
        .aiCreditRecoverySheet(
            issue: $creditAccessIssue,
            settings: appStore.aiSettings,
            onResolved: {
                await MainActor.run {
                    aiError = nil
                    if let set { analyze(set) }
                }
            }
        )
    }

    private func canAnalyze(_ set: BodyPhotoSet) -> Bool {
        !set.angleEntries.isEmpty
            && appStore.aiSettings.isEnabled
            && appStore.aiSettings.dataSharing.bodyPhotos
    }

    private func analyze(_ set: BodyPhotoSet) {
        let inputs = set.angleEntries.compactMap { entry -> BodyPhotoAnalysisInput? in
            guard let imageData = entry.imageData else { return nil }
            return BodyPhotoAnalysisInput(angle: entry.angle, imageData: imageData)
        }
        guard !inputs.isEmpty else { return }

        isAnalyzing = true
        aiError = nil
        let transmission = AITransmissionRecord(
            purpose: L10n.string("health_meals_body_ai.c7dfdfe56ee4", fallback: "体型写真セット解析"),
            sharedCategories: [L10n.string("health_meals_body_ai.f47d6f2e6ec3", fallback: "体型写真")],
            itemCount: inputs.count
        )
        appStore.saveAITransmission(transmission)

        Task {
            do {
                let comment = try await AIAPIClient(settings: appStore.aiSettings)
                    .analyzeBodyPhotos(
                        inputs,
                        memo: set.memo,
                        context: bodyPhotoAnalysisContext(appStore: appStore, date: set.date),
                        previousPhotos: previousBodyPhotoInputs(appStore: appStore, before: set.date)
                    )
                appStore.updateBodyPhotoSetAnalysis(on: set.date, comment: comment)
                appStore.saveMissingBodyPhotoEstimates(from: comment, at: set.date)
                appStore.updateAITransmission(id: transmission.id, status: .completed)
            } catch {
                appStore.recordAITransmissionFailure(id: transmission.id, error: error)
                aiError = AIClientError.presentation(for: error)
                creditAccessIssue = AICreditAccessIssue(error: error)
            }
            isAnalyzing = false
        }
    }
}

private struct BodyPhotoMeasurementContextCard: View {
    @EnvironmentObject private var appStore: AppStore
    let date: Date

    private let kinds: [BodyMetricKind] = [.bodyWeight, .waist, .bodyFatPercentage]

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.string("health_meals_body_ai.6ea10256c1ff", fallback: "同日の実測KPI"), systemImage: "ruler")
                        .font(.headline)
                    Text(L10n.string("health_meals_body_ai.c51a6e397751", fallback: "写真は見た目の変化、数値は実測で確認します。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                ForEach(kinds) { kind in
                    NavigationLink {
                        BodyMetricDetailView(kind: kind)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: kind.systemImage)
                                .foregroundStyle(metricTint(kind))
                                .frame(width: 26)
                            Text(kind.displayName)
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Text(valueText(for: kind))
                                .font(.subheadline.bold())
                                .foregroundStyle(entry(for: kind) == nil ? AppTheme.accent : AppTheme.ink)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.mutedInk)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("bodyPhotoMetricLink-\(kind.rawValue)")
                }
            }
        }
        .accessibilityIdentifier("bodyPhotoMeasurementContext")
    }

    private func entry(for kind: BodyMetricKind) -> BodyMetricEntry? {
        appStore.bodyMetricEntries(for: kind, on: date).first
    }

    private func valueText(for kind: BodyMetricKind) -> String {
        guard let entry = entry(for: kind) else { return L10n.string("health_meals_body_ai.4c3dac603b36", fallback: "記録する") }
        return AppFormatters.metricValue(entry.value, unit: kind.unit)
    }

    private func metricTint(_ kind: BodyMetricKind) -> Color {
        switch kind {
        case .bodyWeight: AppTheme.blue
        case .waist: AppTheme.orange
        case .bodyFatPercentage: AppTheme.purple
        }
    }
}

private struct BodyPhotoSetOverview: View {
    let set: BodyPhotoSet
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string("health_meals_body_ai.9260bfe7ab30", fallback: "{{value1}}枚", values: [String(describing: set.photoEntries.count)]))
                    .font(.title2.bold())
                Spacer()
                BodyPhotoAnalysisStatus(set: set)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(BodyPhotoAngle.allCases) { angle in
                    if let entry = set.angleEntries.first(where: { $0.angle == angle }) {
                        BodyPhotoDetailImage(entry: entry)
                    } else {
                        BodyPhotoMissingAngle(angle: angle)
                    }
                }
            }

            if !set.memo.isEmpty {
                Label(set.memo, systemImage: "note.text")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
            }
        }
    }
}

private struct BodyPhotoDetailImage: View {
    let entry: BodyPhotoEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = entry.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }

            Text(entry.angle.displayName)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.foregroundOnDark)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppTheme.darkBase.opacity(0.82))
                .padding(7)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.82, contentMode: .fit)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

private struct BodyPhotoMissingAngle: View {
    let angle: BodyPhotoAngle

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
                .font(.title2)
            Text(angle.displayName)
                .font(.subheadline.bold())
        }
        .foregroundStyle(AppTheme.mutedInk)
        .frame(maxWidth: .infinity)
        .aspectRatio(0.82, contentMode: .fit)
        .background(AppTheme.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [5]))
        }
    }
}

private struct BodyPhotoThumbnail: View {
    let entry: BodyPhotoEntry
    let size: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let data = entry.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "camera.viewfinder")
                        .foregroundStyle(AppTheme.purple)
                }
            }
            .frame(width: size, height: size)
            .background(AppTheme.purple.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))

            Text(entry.angle.displayName)
                .font(.caption2)
                .foregroundStyle(AppTheme.mutedInk)
        }
    }
}

private struct BodyPhotoEditorView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    let existingSet: BodyPhotoSet?
    let onSave: () -> Void

    @State private var imageDataByAngle: [BodyPhotoAngle: Data]
    @State private var entryIDByAngle: [BodyPhotoAngle: UUID]
    @State private var recordedAt: Date
    @State private var removedAngles: Set<BodyPhotoAngle> = []
    @State private var memo: String
    @State private var aiComment: BodyPhotoAIComment?
    @State private var isAnalyzing = false
    @State private var aiError: AIErrorPresentation?
    @State private var creditAccessIssue: AICreditAccessIssue?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    init(existingSet: BodyPhotoSet? = nil, onSave: @escaping () -> Void) {
        self.existingSet = existingSet
        self.onSave = onSave
        let entries = existingSet?.angleEntries ?? []
        _imageDataByAngle = State(
            initialValue: Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
                entry.imageData.map { (entry.angle, $0) }
            })
        )
        _entryIDByAngle = State(initialValue: Dictionary(uniqueKeysWithValues: entries.map { ($0.angle, $0.id) }))
        _recordedAt = State(initialValue: RecordDatePolicy.normalizedDay(existingSet?.recordedAt ?? Date()))
        _memo = State(initialValue: existingSet?.memo ?? "")
        _aiComment = State(initialValue: existingSet?.analysis)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        L10n.string("health_meals_body_ai.c5deaf60f00d", fallback: "記録日"),
                        selection: $recordedAt,
                        in: RecordDatePolicy.allowedRange(),
                        displayedComponents: .date
                    )

                    BodyPhotoCaptureGuide()

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(BodyPhotoAngle.allCases) { angle in
                            BodyPhotoSlotEditor(
                                angle: angle,
                                imageData: imageDataByAngle[angle],
                                onSelect: { data in
                                    imageDataByAngle[angle] = data
                                    removedAngles.remove(angle)
                                    aiComment = nil
                                    aiError = nil
                                },
                                onRemove: {
                                    imageDataByAngle.removeValue(forKey: angle)
                                    removedAngles.insert(angle)
                                    aiComment = nil
                                    aiError = nil
                                }
                            )
                        }
                    }

                    Text(L10n.string("health_meals_body_ai.4c7bd8cd9b27", fallback: "正面・横・背面などを同じ日にまとめます。1枚でも保存でき、後から追加できます。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                } header: {
                    Text(L10n.string("health_meals_body_ai.7f4a4ef3a2a5", fallback: "撮影方向"))
                } footer: {
                    Text(L10n.string("health_meals_body_ai.8f378a32aed7", fallback: "現在 {{value1}}/4枚", values: [String(describing: imageDataByAngle.count)]))
                }

                Section(L10n.string("health_meals_body_ai.03b5d7044111", fallback: "メモ")) {
                    TextField(L10n.string("health_meals_body_ai.71bec5b80d72", fallback: "撮影条件や見た目のメモ"), text: $memo, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .accessibilityIdentifier("bodyPhotoMemoField")
                }

                Section(L10n.string("health_meals_body_ai.f74c6003db3a", fallback: "AI分析")) {
                    CoachIdentityView(
                        persona: appStore.userProfile.coachPersona,
                        role: L10n.string("health_meals_body_ai.e208549633cc", fallback: "体型写真チェック"),
                        detail: L10n.string("health_meals_body_ai.4d8687bed4f2", fallback: "複数方向の写真をまとめて確認します。"),
                        avatarSize: 48
                    )
                    .accessibilityIdentifier("bodyPhotoAICoachIdentity")

                    AICreditCostStatusView(feature: "body_photo", settings: appStore.aiSettings)

                    Button {
                        analyzeCurrentPhotos()
                    } label: {
                        Label(
                            isAnalyzing ? L10n.string("health_meals_body_ai.ce7cce7b48e4", fallback: "セットを分析中") : (aiComment == nil ? L10n.string("health_meals_body_ai.ff3c57454258", fallback: "写真をまとめて分析") : L10n.string("health_meals_body_ai.d5b6606496a9", fallback: "写真をまとめて再分析")),
                            systemImage: "sparkles"
                        )
                    }
                    .disabled(!canAnalyze || isAnalyzing)
                    .accessibilityIdentifier("analyzeBodyPhotoButton")

                    Text(aiHelpText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }

                if let aiComment {
                    Section(L10n.string("health_meals_body_ai.5c0fab317f2b", fallback: "{{value1}}の分析結果", values: [String(describing: appStore.userProfile.coachPersona.displayName)])) {
                        CoachAttributionLabel(
                            persona: appStore.userProfile.coachPersona,
                            text: L10n.string("health_meals_body_ai.d82ca70d9996", fallback: "見た目の変化を参考として確認")
                        )
                        BodyPhotoAICommentContent(comment: aiComment)
                    }
                }

                if let aiError {
                    Section(L10n.string("health_meals_body_ai.7d80eebb209d", fallback: "AIエラー")) {
                        BodyPhotoAIErrorCard(error: aiError)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(existingSet == nil ? L10n.string("health_meals_body_ai.83b51a58d083", fallback: "撮影セットを追加") : L10n.string("health_meals_body_ai.a024d937dc43", fallback: "撮影セットを編集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("health_meals_body_ai.dd84abcb6681", fallback: "キャンセル")) { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.string("health_meals_body_ai.1e18f9b0644c", fallback: "保存")) { save() }
                        .disabled(imageDataByAngle.isEmpty && memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveBodyPhotoButton")
                }
            }
            .aiCreditRecoverySheet(
                issue: $creditAccessIssue,
                settings: appStore.aiSettings,
                onResolved: {
                    await MainActor.run {
                        aiError = nil
                        analyzeCurrentPhotos()
                    }
                }
            )
        }
    }

    private var canAnalyze: Bool {
        !imageDataByAngle.isEmpty
            && appStore.aiSettings.isEnabled
            && appStore.aiSettings.dataSharing.bodyPhotos
    }

    private var aiHelpText: String {
        if !appStore.aiSettings.isEnabled { return L10n.string("health_meals_body_ai.215d8802d90e", fallback: "AI機能は設定でオフです。写真セットはこのまま保存できます。") }
        if !appStore.aiSettings.dataSharing.bodyPhotos { return L10n.string("health_meals_body_ai.33222467ebe4", fallback: "体型写真のAI共有は設定でオフです。") }
        if imageDataByAngle.isEmpty { return L10n.string("health_meals_body_ai.c5c93f735c29", fallback: "写真を1枚以上選ぶと分析できます。複数方向があるほど確認しやすくなります。") }
        if imageDataByAngle.count == 1 { return L10n.string("health_meals_body_ai.15277ebacd5d", fallback: "このまま分析できます。横や背面も追加すると、別方向から補って確認できます。") }
        return L10n.string("health_meals_body_ai.7d4f39ef9618", fallback: "{{value1}}方向の写真をまとめて分析します。体脂肪率などの数値は断定しません。", values: [String(describing: imageDataByAngle.count)])
    }

    private func analyzeCurrentPhotos() {
        let normalizedDate = RecordDatePolicy.normalizedDay(recordedAt)
        let inputs = BodyPhotoAngle.allCases.compactMap { angle in
            imageDataByAngle[angle].map { BodyPhotoAnalysisInput(angle: angle, imageData: $0) }
        }
        guard !inputs.isEmpty else { return }

        isAnalyzing = true
        aiError = nil
        let transmission = AITransmissionRecord(
            purpose: L10n.string("health_meals_body_ai.c7dfdfe56ee4", fallback: "体型写真セット解析"),
            sharedCategories: [L10n.string("health_meals_body_ai.f47d6f2e6ec3", fallback: "体型写真")],
            itemCount: inputs.count
        )
        appStore.saveAITransmission(transmission)

        Task {
            do {
                let comment = try await AIAPIClient(settings: appStore.aiSettings)
                    .analyzeBodyPhotos(
                        inputs,
                        memo: memo,
                        context: bodyPhotoAnalysisContext(
                            appStore: appStore,
                            date: normalizedDate
                        ),
                        previousPhotos: previousBodyPhotoInputs(
                            appStore: appStore,
                            before: normalizedDate
                        )
                    )
                aiComment = comment
                appStore.saveMissingBodyPhotoEstimates(from: comment, at: normalizedDate)
                appStore.updateAITransmission(id: transmission.id, status: .completed)
            } catch {
                appStore.recordAITransmissionFailure(id: transmission.id, error: error)
                aiError = AIClientError.presentation(for: error)
                creditAccessIssue = AICreditAccessIssue(error: error)
            }
            isAnalyzing = false
        }
    }

    private func save() {
        let targetDate = RecordDatePolicy.normalizedDay(existingSet?.date ?? Date())
        let normalizedRecordedAt = RecordDatePolicy.normalizedDay(recordedAt)
        var entries = BodyPhotoAngle.allCases.compactMap { angle -> BodyPhotoEntry? in
            guard let imageData = imageDataByAngle[angle] else { return nil }
            return BodyPhotoEntry(
                id: entryIDByAngle[angle] ?? UUID(),
                recordedAt: normalizedRecordedAt,
                angle: angle,
                memo: memo,
                imageData: imageData,
                aiComment: aiComment
            )
        }

        if entries.isEmpty {
            entries = [
                BodyPhotoEntry(
                    id: existingSet?.entries.first?.id ?? UUID(),
                    recordedAt: normalizedRecordedAt,
                    angle: existingSet?.entries.first?.angle ?? .front,
                    memo: memo
                )
            ]
        }

        appStore.saveBodyPhotoSet(
            entries,
            replacing: targetDate,
            removingAngles: removedAngles
        )
        onSave()
        dismiss()
    }
}

private struct BodyPhotoSlotEditor: View {
    let angle: BodyPhotoAngle
    let imageData: Data?
    let onSelect: (Data) -> Void
    let onRemove: () -> Void

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var isShowingCameraPermissionAlert = false

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let imageData, let image = UIImage(data: imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: angle.systemImage)
                                .font(.system(size: 38, weight: .medium))
                                .foregroundStyle(AppTheme.mutedInk)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }

                    Text(angle.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(imageData == nil ? AppTheme.ink : AppTheme.foregroundOnDark)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(imageData == nil ? AppTheme.cardBackground.opacity(0.9) : AppTheme.darkBase.opacity(0.82))
                        .padding(6)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(0.82, contentMode: .fit)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }
                if imageData != nil {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(AppTheme.foregroundOnDark, AppTheme.darkBase.opacity(0.85))
                    }
                    .padding(6)
                    .accessibilityLabel(L10n.string("health_meals_body_ai.156dec7f8ca6", fallback: "{{value1}}写真を削除", values: [String(describing: angle.displayName)]))
                }
            }

            HStack(spacing: 6) {
                Button {
                    requestCameraAccess()
                } label: {
                    Image(systemName: "camera.fill")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                .accessibilityLabel(L10n.string("health_meals_body_ai.d715189703aa", fallback: "{{value1}}を撮影", values: [String(describing: angle.displayName)]))
                .accessibilityIdentifier("bodyPhotoCamera-\(angle.rawValue)")

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(L10n.string("health_meals_body_ai.ec33ef8cdb99", fallback: "{{value1}}をライブラリから選択", values: [String(describing: angle.displayName)]))
                .accessibilityIdentifier(angle == .front ? "bodyPhotoPicker" : "bodyPhotoPicker-\(angle.rawValue)")
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                let processed = (try? AIImageUploadProcessor.jpegData(from: data)) ?? data
                await MainActor.run { onSelect(processed) }
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraImagePicker { data in
                isShowingCamera = false
                onSelect((try? AIImageUploadProcessor.jpegData(from: data)) ?? data)
            } onCancel: {
                isShowingCamera = false
            }
            .ignoresSafeArea()
        }
        .alert(L10n.string("health_meals_body_ai.188fd18847ac", fallback: "カメラを使用できません"), isPresented: $isShowingCameraPermissionAlert) {
            Button(L10n.string("health_meals_body_ai.1ed3ceaf4396", fallback: "設定を開く")) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            Button(L10n.string("health_meals_body_ai.dd84abcb6681", fallback: "キャンセル"), role: .cancel) {}
        } message: {
            Text(L10n.string("health_meals_body_ai.576015450b34", fallback: "設定でBodyModeのカメラ利用を許可してください。"))
        }
    }

    private func requestCameraAccess() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                await MainActor.run {
                    if granted {
                        isShowingCamera = true
                    } else {
                        isShowingCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            isShowingCameraPermissionAlert = true
        @unknown default:
            isShowingCameraPermissionAlert = true
        }
    }
}

private struct BodyPhotoCaptureGuide: View {
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image("BodyPhotoCaptureGuide")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                .accessibilityHidden(true)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(BodyPhotoAngle.allCases) { angle in
                    Label(angle.guideLabel, systemImage: angle.guideSystemImage)
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Label(L10n.string("health_meals_body_ai.4127c532bfe3", fallback: "同じ服・距離・光で、力を抜いて撮影"), systemImage: "camera.metering.center.weighted")
                .font(.caption)
                .foregroundStyle(AppTheme.mutedInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("health_meals_body_ai.1400ab3be8e8", fallback: "撮影見本。左上は正面全身、右上は真横全身、左下は背面全身、右下は肩から腰までの腹部アップ。同じ服、距離、光で撮影"))
        .accessibilityIdentifier("bodyPhotoCaptureGuide")
    }
}

private extension BodyPhotoAngle {
    var systemImage: String {
        switch self {
        case .front: "figure.stand"
        case .side: "figure.stand.line.dotted.figure.stand"
        case .back: "figure.walk"
        case .abdomen: "viewfinder"
        }
    }

    var guideSystemImage: String {
        switch self {
        case .front: "arrow.up"
        case .side: "arrow.right"
        case .back: "arrow.down"
        case .abdomen: "viewfinder"
        }
    }

    var guideLabel: String {
        switch self {
        case .front: L10n.string("health_meals_body_ai.f848634a1768", fallback: "左上  正面・全身")
        case .side: L10n.string("health_meals_body_ai.9ab9099ebccb", fallback: "右上  真横・全身")
        case .back: L10n.string("health_meals_body_ai.15292dad18bc", fallback: "左下  背面・全身")
        case .abdomen: L10n.string("health_meals_body_ai.ca55f072b646", fallback: "右下  肩〜腰")
        }
    }
}

private struct BodyPhotoAICommentCard: View {
    let comment: BodyPhotoAIComment
    let coachPersona: CoachPersona

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CoachAttributionLabel(
                    persona: coachPersona,
                    text: L10n.string("health_meals_body_ai.356ec7e292c8", fallback: "{{value1}}の分析", values: [String(describing: coachPersona.displayName)])
                )
                BodyPhotoAICommentContent(comment: comment)
            }
        }
    }
}

private struct BodyPhotoAICommentContent: View {
    let comment: BodyPhotoAIComment
    @State private var isShowingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(comment.summary)
                .font(.body.weight(.semibold))
                .accessibilityIdentifier("bodyPhotoAnalysisSummary")

            if let firstAction = comment.nextActions?.first, !firstAction.isEmpty {
                Label(firstAction, systemImage: "arrow.forward.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityIdentifier("bodyPhotoAnalysisFirstAction")
            }

            if let estimates = comment.referenceEstimates, !estimates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.string("health_meals_body_ai.9cddd80a2f5a", fallback: "写真からの参考範囲"), systemImage: "ruler.fill")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.warning)
                    ForEach(estimates) { estimate in
                        Text(
                            "\(estimate.displayName) "
                            + "\(estimate.lowerBound.formatted(.number.precision(.fractionLength(0...1))))"
                            + "〜\(estimate.upperBound.formatted(.number.precision(.fractionLength(0...1))))"
                            + "\(estimate.unit)"
                        )
                        .font(.subheadline.bold())
                    }
                    Text(L10n.string("health_meals_body_ai.103eefbf9842", fallback: "低信頼度の参考値です。同日の未入力項目には推定値として自動記録します。実測値は上書きしません。"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedInk)
                }
                .padding(10)
                .background(AppTheme.warning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                .accessibilityIdentifier("bodyPhotoReferenceEstimates")
            }

            DisclosureGroup(L10n.string("health_meals_body_ai.419ad2a6aa29", fallback: "詳しい分析"), isExpanded: $isShowingDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    if let goalRelevance = comment.goalRelevance, !goalRelevance.isEmpty {
                        BodyPhotoObservation(label: L10n.string("health_meals_body_ai.6d0bcffe314f", fallback: "目標への意味"), value: goalRelevance)
                    }
                    if let positiveFindings = comment.positiveFindings, !positiveFindings.isEmpty {
                        BodyPhotoBulletList(label: L10n.string("health_meals_body_ai.7645e396f538", fallback: "良い点"), items: positiveFindings)
                    }
                    if let observedChanges = comment.observedChanges, !observedChanges.isEmpty {
                        BodyPhotoBulletList(label: L10n.string("health_meals_body_ai.8466e434074d", fallback: "確認できた変化"), items: observedChanges)
                    }
                    if let nextActions = comment.nextActions, !nextActions.isEmpty {
                        BodyPhotoBulletList(label: L10n.string("health_meals_body_ai.92f1e4be7323", fallback: "次の一手"), items: Array(nextActions.prefix(3)))
                    }
                    BodyPhotoObservation(label: L10n.string("health_meals_body_ai.a038994e000b", fallback: "腹部"), value: comment.abdomen)
                    BodyPhotoObservation(label: L10n.string("health_meals_body_ai.12006fd0cc46", fallback: "ウエスト"), value: comment.waist)
                    BodyPhotoObservation(label: L10n.string("health_meals_body_ai.0eb1cd5802d6", fallback: "姿勢"), value: comment.posture)
                    HStack {
                        Text(L10n.string("health_meals_body_ai.7421e1ca9b5b", fallback: "信頼度"))
                        Spacer()
                        Text(comment.confidence)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    .font(.footnote)
                }
                .padding(.top, 8)
            }
            .font(.subheadline.bold())
            .accessibilityIdentifier("bodyPhotoAnalysisDetails")
        }
    }
}

private struct BodyPhotoBulletList: View {
    let label: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.accent)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)
            }
        }
    }
}

@MainActor
func bodyPhotoAnalysisContext(appStore: AppStore, date: Date) -> BodyPhotoAnalysisContext {
    let profile = appStore.userProfile
    let startOfDay = Calendar.current.startOfDay(for: date)
    let previousSet = appStore.bodyPhotoSets.first {
        $0.date < startOfDay
    }
    let currentValues: [BodyMetricKind: Double] = Dictionary(
        uniqueKeysWithValues: BodyMetricKind.allCases.compactMap { kind -> (BodyMetricKind, Double)? in
            appStore.bodyMetricEntries(for: kind, on: date).first.map { (kind, $0.value) }
        }
    )
    let previousValues: [BodyMetricKind: Double] = Dictionary(
        uniqueKeysWithValues: BodyMetricKind.allCases.compactMap { kind -> (BodyMetricKind, Double)? in
            guard let previousDate = previousSet?.date else { return nil }
            return appStore.bodyMetricEntries(for: kind, on: previousDate).first.map { (kind, $0.value) }
        }
    )
    let metrics = BodyMetricKind.allCases.compactMap { kind -> String? in
        guard let value = currentValues[kind] else { return nil }
        return "\(kind.displayName): \(AppFormatters.metricValue(value, unit: kind.unit))"
    }
    let previousMetrics = bodyPhotoMetrics(from: previousValues)
    let metricDeltas = bodyPhotoMetrics(
        from: Dictionary(
            uniqueKeysWithValues: BodyMetricKind.allCases.compactMap { kind -> (BodyMetricKind, Double)? in
                guard let current = currentValues[kind], let previous = previousValues[kind] else { return nil }
                return (kind, current - previous)
            }
        )
    )
    let outcome = profile.outcomeStyle == .custom && !profile.customOutcomeText.isEmpty
        ? profile.customOutcomeText
        : profile.outcomeStyle.displayName

    return BodyPhotoAnalysisContext(
        profileGoal: profile.goalType.displayName,
        outcomeStyle: outcome,
        focusAreas: profile.focusMuscles.map(\.displayName),
        experienceLevel: profile.experienceLevel.displayName,
        currentMetrics: metrics,
        previousCaptureDate: previousSet?.date.formatted(.iso8601.year().month().day()),
        previousSummary: previousSet?.analysis?.summary,
        previousMetrics: previousMetrics,
        metricDeltas: metricDeltas,
        coach: AIRequestCoachContext(profile: profile)
    )
}

private func bodyPhotoMetrics(from values: [BodyMetricKind: Double]) -> BodyPhotoAnalysisMetrics? {
    let metrics = BodyPhotoAnalysisMetrics(
        weightKG: values[.bodyWeight],
        waistCM: values[.waist],
        bodyFatPercentage: values[.bodyFatPercentage]
    )
    return metrics.isEmpty ? nil : metrics
}

@MainActor
private func previousBodyPhotoInputs(appStore: AppStore, before date: Date) -> [BodyPhotoAnalysisInput] {
    guard let previousSet = appStore.bodyPhotoSets.first(where: {
        $0.date < Calendar.current.startOfDay(for: date)
    }) else { return [] }

    return previousSet.angleEntries.compactMap { entry in
        entry.imageData.map { BodyPhotoAnalysisInput(angle: entry.angle, imageData: $0) }
    }
}

private struct BodyPhotoObservation: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.accent)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
        }
    }
}

private struct BodyPhotoAIErrorCard: View {
    let error: AIErrorPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "xmark.octagon.fill")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.critical)
            if let recovery = error.recovery {
                Text(recovery)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }
            Text(L10n.string("health_meals_body_ai.e9872cc8c9d1", fallback: "写真セットは保存できます。接続後にセット詳細から再分析できます。"))
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
        }
        .accessibilityIdentifier("bodyPhotoAIErrorRecoveryCard")
    }
}

#Preview {
    BodyPhotoListView()
        .environmentObject(AppStore())
}
