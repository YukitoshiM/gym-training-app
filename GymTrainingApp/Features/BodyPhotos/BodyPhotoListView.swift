import PhotosUI
import SwiftUI

struct BodyPhotoListView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isShowingEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        MetricPill(title: "今日の写真", value: "\(appStore.bodyPhotoEntries().count)", systemImage: "camera", tint: AppTheme.purple)
                        MetricPill(title: "合計", value: "\(appStore.bodyPhotoEntries.count)", systemImage: "photo.on.rectangle", tint: AppTheme.blue)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section("写真ログ") {
                    if appStore.bodyPhotoEntries.isEmpty {
                        Text("体型写真はまだありません")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 18)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    ForEach(appStore.bodyPhotoEntries) { entry in
                        BodyPhotoRow(entry: entry)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: appStore.deleteBodyPhotoEntries)
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
                        isShowingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("体型写真を追加")
                    .accessibilityIdentifier("addBodyPhotoButton")
                }
            }
            .sheet(isPresented: $isShowingEditor) {
                BodyPhotoEditorView {
                    isShowingEditor = false
                }
            }
        }
    }
}

private struct BodyPhotoRow: View {
    let entry: BodyPhotoEntry

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                BodyPhotoThumbnail(imageData: entry.imageData)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.angle.displayName)
                            .font(.headline)
                        Spacer()
                        Text(entry.imageData == nil ? "メモ" : "写真")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.purple)
                    }

                    Text(AppFormatters.shortDateTime.string(from: entry.recordedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !entry.memo.isEmpty {
                        Text(entry.memo)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let aiComment = entry.aiComment {
                        Label(aiComment.summary, systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("bodyPhotoRow-\(entry.angle.rawValue)")
    }
}

private struct BodyPhotoThumbnail: View {
    let imageData: Data?

    var body: some View {
        Group {
            if let imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "camera.viewfinder")
                    .font(.title2)
                    .foregroundStyle(AppTheme.purple)
            }
        }
        .frame(width: 54, height: 54)
        .background(AppTheme.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

private struct BodyPhotoEditorView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    let onSave: () -> Void

    @State private var angle: BodyPhotoAngle = .front
    @State private var memo = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var aiComment: BodyPhotoAIComment?
    @State private var isAnalyzing = false
    @State private var aiErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("写真") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("写真を選択・変更", systemImage: "photo")
                    }
                    .accessibilityIdentifier("bodyPhotoPicker")

                    if let imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                    }

                    Button {
                        analyzeBodyPhoto()
                    } label: {
                        Label(isAnalyzing ? "AIコメント作成中" : "AIコメントを作成", systemImage: "sparkles")
                    }
                    .disabled(imageData == nil || isAnalyzing)
                    .accessibilityIdentifier("analyzeBodyPhotoButton")
                }

                Section("撮影角度") {
                    Picker("角度", selection: $angle) {
                        ForEach(BodyPhotoAngle.allCases) { angle in
                            Text(angle.displayName).tag(angle)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("bodyPhotoAnglePicker")
                }

                Section("メモ") {
                    TextField("撮影条件や見た目のメモ", text: $memo, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .accessibilityIdentifier("bodyPhotoMemoField")
                }

                if let aiComment {
                    Section("AIコメント") {
                        Text(aiComment.summary)
                            .font(.headline)
                        LabeledContent("腹部", value: aiComment.abdomen)
                        LabeledContent("脇腹", value: aiComment.waist)
                        LabeledContent("姿勢", value: aiComment.posture)
                        if let score = aiComment.score {
                            LabeledContent("見た目スコア", value: score.formatted(.number.precision(.fractionLength(0...1))))
                        }
                        LabeledContent("信頼度", value: aiComment.confidence)
                    }
                }

                if let aiErrorMessage {
                    Section("AIエラー") {
                        Text(aiErrorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("体型写真を記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        save()
                    }
                    .accessibilityIdentifier("saveBodyPhotoButton")
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    imageData = try? await item?.loadTransferable(type: Data.self)
                }
            }
        }
    }

    private func analyzeBodyPhoto() {
        guard let imageData else {
            return
        }

        isAnalyzing = true
        aiErrorMessage = nil

        Task {
            do {
                let comment = try await LocalAIClient(settings: appStore.aiSettings)
                    .analyzeBodyPhoto(imageData: imageData, angle: angle, memo: memo)
                await MainActor.run {
                    aiComment = comment
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    aiErrorMessage = error.localizedDescription
                    isAnalyzing = false
                }
            }
        }
    }

    private func save() {
        appStore.saveBodyPhotoEntry(
            BodyPhotoEntry(
                angle: angle,
                memo: memo,
                imageData: imageData,
                aiComment: aiComment
            )
        )
        onSave()
    }
}

#Preview {
    BodyPhotoListView()
        .environmentObject(AppStore())
}
