import SwiftUI

struct DeletedRecordsView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isConfirmingEmpty = false

    var body: some View {
        List {
            if appStore.deletedRecords.isEmpty {
                ContentUnavailableView(
                    L10n.string("core_ui.trash_empty", fallback: "ゴミ箱は空です"),
                    systemImage: "trash",
                    description: Text(L10n.string("core_ui.trash_retention", fallback: "削除した記録は30日間ここに残ります。"))
                )
            } else {
                Section {
                    ForEach(appStore.deletedRecords) { record in
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: record.payload))
                                .font(.title3)
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.title)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(2)
                                Text(record.deletedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.mutedInk)
                            }
                            Spacer()
                            Button {
                                appStore.restoreDeletedRecord(record.id)
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.string("core_ui.restore_record", fallback: "記録を復元"))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                appStore.permanentlyDeleteRecord(record.id)
                            } label: {
                                Label(L10n.string("core_ui.delete_permanently", fallback: "完全に削除"), systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text(L10n.string("core_ui.trash_retention", fallback: "削除した記録は30日間ここに残ります。"))
                }

                Section {
                    Button(role: .destructive) {
                        isConfirmingEmpty = true
                    } label: {
                        Label(L10n.string("core_ui.empty_trash", fallback: "ゴミ箱を空にする"), systemImage: "trash.slash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle(L10n.string("core_ui.trash", fallback: "ゴミ箱"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            L10n.string("core_ui.empty_trash_confirm", fallback: "すべて完全に削除しますか？"),
            isPresented: $isConfirmingEmpty,
            titleVisibility: .visible
        ) {
            Button(L10n.string("core_ui.empty_trash", fallback: "ゴミ箱を空にする"), role: .destructive) {
                appStore.emptyTrash()
            }
            Button(L10n.string("core_ui.37a3754927b6", fallback: "キャンセル"), role: .cancel) {}
        }
    }

    private func icon(for payload: DeletedRecordPayload) -> String {
        switch payload {
        case .trainingPlan: "list.clipboard"
        case .activeWorkout: "pause.circle.fill"
        case .workout: "dumbbell.fill"
        case .meal: "fork.knife"
        case .bodyPhotos: "photo.on.rectangle"
        case .bodyMetric: "scalemass"
        case .customExercise: "figure.strengthtraining.traditional"
        case .gymVisit: "mappin.and.ellipse"
        case .subjectiveRecovery: "waveform.path.ecg"
        case .coachMemory, .coachChatMessage, .aiInsight: "sparkles"
        case .aiTransmission: "arrow.up.arrow.down.circle"
        }
    }
}
