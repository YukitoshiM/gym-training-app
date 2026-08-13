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
                            title: "今日のセット",
                            value: appStore.bodyPhotoSet() == nil ? "0" : "1",
                            systemImage: "camera",
                            tint: AppTheme.purple
                        )
                        MetricPill(
                            title: "撮影日数",
                            value: "\(appStore.bodyPhotoSets.count)",
                            systemImage: "calendar",
                            tint: AppTheme.blue
                        )
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section("撮影セット") {
                    if appStore.bodyPhotoSets.isEmpty {
                        ContentUnavailableView(
                            "体型写真はまだありません",
                            systemImage: "camera.viewfinder",
                            description: Text("正面・横・背面などを1日分のセットとして記録します。")
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
            .navigationTitle("体型写真")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorRequest = BodyPhotoEditorRequest(set: appStore.bodyPhotoSet())
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(appStore.bodyPhotoSet() == nil ? "今日の撮影セットを追加" : "今日の撮影セットを編集")
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
                        Text("\(set.photoEntries.count)枚の撮影セット")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    Spacer()

                    BodyPhotoAnalysisStatus(set: set)
                }

                if set.angleEntries.isEmpty {
                    Label(set.memo.isEmpty ? "写真を追加" : set.memo, systemImage: "camera.viewfinder")
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
        if set.photoEntries.isEmpty { return "写真なし" }
        if set.needsAnalysis { return set.analysis == nil ? "未分析" : "再分析が必要" }
        return "分析済み"
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
                                    text: "\(appStore.userProfile.coachPersona.displayName)がセット全体を確認"
                                )
                                Text("複数方向の写真をまとめて送ると、正面だけでは分からない姿勢や体型を補い合って確認できます。")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                        }
                    }

                    if let aiError {
                        BodyPhotoAIErrorCard(error: aiError)
                    }

                    VStack(spacing: 10) {
                        Button {
                            analyze(set)
                        } label: {
                            Label(
                                isAnalyzing ? "分析中" : (set.analysis == nil ? "このセットを分析" : "写真をまとめて再分析"),
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
                            Label("写真を追加・編集", systemImage: "photo.badge.plus")
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
            purpose: "体型写真セット解析",
            sharedCategories: ["体型写真"],
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
                appStore.updateAITransmission(id: transmission.id, status: .completed)
            } catch {
                appStore.updateAITransmission(id: transmission.id, status: .failed)
                aiError = AIClientError.presentation(for: error)
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
                    Label("同日の実測KPI", systemImage: "ruler")
                        .font(.headline)
                    Text("写真は見た目の変化、数値は実測で確認します。")
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
        guard let entry = entry(for: kind) else { return "記録する" }
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
                Text("\(set.photoEntries.count)枚")
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
    @State private var recordedAtByAngle: [BodyPhotoAngle: Date]
    @State private var memo: String
    @State private var aiComment: BodyPhotoAIComment?
    @State private var isAnalyzing = false
    @State private var aiError: AIErrorPresentation?

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
        _recordedAtByAngle = State(initialValue: Dictionary(uniqueKeysWithValues: entries.map { ($0.angle, $0.recordedAt) }))
        _memo = State(initialValue: existingSet?.memo ?? "")
        _aiComment = State(initialValue: existingSet?.analysis)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BodyPhotoCaptureGuide()

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(BodyPhotoAngle.allCases) { angle in
                            BodyPhotoSlotEditor(
                                angle: angle,
                                imageData: imageDataByAngle[angle],
                                onSelect: { data in
                                    imageDataByAngle[angle] = data
                                    aiComment = nil
                                    aiError = nil
                                },
                                onRemove: {
                                    imageDataByAngle.removeValue(forKey: angle)
                                    aiComment = nil
                                    aiError = nil
                                }
                            )
                        }
                    }

                    Text("正面・横・背面などを同じ日にまとめます。1枚でも保存でき、後から追加できます。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                } header: {
                    Text("撮影方向")
                } footer: {
                    Text("現在 \(imageDataByAngle.count)/4枚")
                }

                Section("メモ") {
                    TextField("撮影条件や見た目のメモ", text: $memo, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .accessibilityIdentifier("bodyPhotoMemoField")
                }

                Section("AI分析") {
                    CoachIdentityView(
                        persona: appStore.userProfile.coachPersona,
                        role: "体型写真チェック",
                        detail: "複数方向の写真をまとめて確認します。",
                        avatarSize: 48
                    )
                    .accessibilityIdentifier("bodyPhotoAICoachIdentity")

                    Button {
                        analyzeCurrentPhotos()
                    } label: {
                        Label(
                            isAnalyzing ? "セットを分析中" : (aiComment == nil ? "写真をまとめて分析" : "写真をまとめて再分析"),
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
                    Section("\(appStore.userProfile.coachPersona.displayName)の分析結果") {
                        CoachAttributionLabel(
                            persona: appStore.userProfile.coachPersona,
                            text: "見た目の変化を参考として確認"
                        )
                        BodyPhotoAICommentContent(comment: aiComment)
                    }
                }

                if let aiError {
                    Section("AIエラー") {
                        BodyPhotoAIErrorCard(error: aiError)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(existingSet == nil ? "撮影セットを追加" : "撮影セットを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("保存") { save() }
                        .disabled(imageDataByAngle.isEmpty && memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveBodyPhotoButton")
                }
            }
        }
    }

    private var canAnalyze: Bool {
        !imageDataByAngle.isEmpty
            && appStore.aiSettings.isEnabled
            && appStore.aiSettings.dataSharing.bodyPhotos
    }

    private var aiHelpText: String {
        if !appStore.aiSettings.isEnabled { return "AI機能は設定でオフです。写真セットはこのまま保存できます。" }
        if !appStore.aiSettings.dataSharing.bodyPhotos { return "体型写真のAI共有は設定でオフです。" }
        if imageDataByAngle.isEmpty { return "写真を1枚以上選ぶと分析できます。複数方向があるほど確認しやすくなります。" }
        if imageDataByAngle.count == 1 { return "このまま分析できます。横や背面も追加すると、別方向から補って確認できます。" }
        return "\(imageDataByAngle.count)方向の写真をまとめて分析します。体脂肪率などの数値は断定しません。"
    }

    private func analyzeCurrentPhotos() {
        let inputs = BodyPhotoAngle.allCases.compactMap { angle in
            imageDataByAngle[angle].map { BodyPhotoAnalysisInput(angle: angle, imageData: $0) }
        }
        guard !inputs.isEmpty else { return }

        isAnalyzing = true
        aiError = nil
        let transmission = AITransmissionRecord(
            purpose: "体型写真セット解析",
            sharedCategories: ["体型写真"],
            itemCount: inputs.count
        )
        appStore.saveAITransmission(transmission)

        Task {
            do {
                aiComment = try await AIAPIClient(settings: appStore.aiSettings)
                    .analyzeBodyPhotos(
                        inputs,
                        memo: memo,
                        context: bodyPhotoAnalysisContext(
                            appStore: appStore,
                            date: existingSet?.date ?? Date()
                        ),
                        previousPhotos: previousBodyPhotoInputs(
                            appStore: appStore,
                            before: existingSet?.date ?? Date()
                        )
                    )
                appStore.updateAITransmission(id: transmission.id, status: .completed)
            } catch {
                appStore.updateAITransmission(id: transmission.id, status: .failed)
                aiError = AIClientError.presentation(for: error)
            }
            isAnalyzing = false
        }
    }

    private func save() {
        let targetDate = existingSet?.date ?? Date()
        let defaultRecordedAt = existingSet?.recordedAt ?? Date()
        var entries = BodyPhotoAngle.allCases.compactMap { angle -> BodyPhotoEntry? in
            guard let imageData = imageDataByAngle[angle] else { return nil }
            return BodyPhotoEntry(
                id: entryIDByAngle[angle] ?? UUID(),
                recordedAt: recordedAtByAngle[angle] ?? defaultRecordedAt,
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
                    recordedAt: existingSet?.recordedAt ?? Date(),
                    angle: existingSet?.entries.first?.angle ?? .front,
                    memo: memo
                )
            ]
        }

        appStore.saveBodyPhotoSet(entries, replacing: targetDate)
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
                    .accessibilityLabel("\(angle.displayName)写真を削除")
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
                .accessibilityLabel("\(angle.displayName)を撮影")
                .accessibilityIdentifier("bodyPhotoCamera-\(angle.rawValue)")

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(angle.displayName)をライブラリから選択")
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
        .alert("カメラを使用できません", isPresented: $isShowingCameraPermissionAlert) {
            Button("設定を開く") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("設定でBodyModeのカメラ利用を許可してください。")
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
    var body: some View {
        HStack(spacing: 8) {
            guideItem("全身", systemImage: "figure.stand")
            guideItem("同じ距離", systemImage: "arrow.left.and.right")
            guideItem("同じ光", systemImage: "sun.max")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("撮影ガイド。全身、同じ距離、同じ光で撮影")
    }

    private func guideItem(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.caption2.bold())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
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
}

private struct BodyPhotoAICommentCard: View {
    let comment: BodyPhotoAIComment
    let coachPersona: CoachPersona

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CoachAttributionLabel(
                    persona: coachPersona,
                    text: "\(coachPersona.displayName)の分析"
                )
                BodyPhotoAICommentContent(comment: comment)
            }
        }
    }
}

private struct BodyPhotoAICommentContent: View {
    let comment: BodyPhotoAIComment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(comment.summary)
                .font(.body.weight(.semibold))
            if let goalRelevance = comment.goalRelevance, !goalRelevance.isEmpty {
                BodyPhotoObservation(label: "目標への意味", value: goalRelevance)
            }
            if let positiveFindings = comment.positiveFindings, !positiveFindings.isEmpty {
                BodyPhotoBulletList(label: "良い点", items: positiveFindings)
            }
            if let observedChanges = comment.observedChanges, !observedChanges.isEmpty {
                BodyPhotoBulletList(label: "確認できた変化", items: observedChanges)
            }
            if let nextActions = comment.nextActions, !nextActions.isEmpty {
                BodyPhotoBulletList(label: "次の一手", items: Array(nextActions.prefix(3)))
            }
            BodyPhotoObservation(label: "腹部", value: comment.abdomen)
            BodyPhotoObservation(label: "ウエスト", value: comment.waist)
            BodyPhotoObservation(label: "姿勢", value: comment.posture)
            HStack {
                Text("信頼度")
                Spacer()
                Text(comment.confidence)
                    .foregroundStyle(AppTheme.mutedInk)
            }
            .font(.footnote)
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
            Text("写真セットは保存できます。接続後にセット詳細から再分析できます。")
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
