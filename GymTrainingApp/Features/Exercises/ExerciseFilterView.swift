import SwiftUI

struct ExerciseFilterView: View {
    @Binding var selectedMuscle: MuscleGroup?
    @Binding var selectedEquipment: Equipment?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FilterRow(
                title: L10n.string("training.78efc5de2d26", fallback: "部位"),
                systemImage: "figure.strengthtraining.traditional",
                allTitle: L10n.string("training.c7fe2b510de0", fallback: "すべて"),
                items: MuscleGroup.selectionCases,
                selectedItem: $selectedMuscle,
                titleForItem: \.displayName,
                iconForItem: { $0.systemImage }
            )

            FilterRow(
                title: L10n.string("training.a0c4d068d3f0", fallback: "手法"),
                systemImage: "dumbbell",
                allTitle: L10n.string("training.c7fe2b510de0", fallback: "すべて"),
                items: Equipment.allCases,
                selectedItem: $selectedEquipment,
                titleForItem: \.displayName,
                iconForItem: { $0.systemImage }
            )
        }
        .padding(.vertical, 4)
    }
}

private struct FilterRow<Item: Identifiable & Hashable>: View {
    let title: String
    let systemImage: String
    let allTitle: String
    let items: [Item]
    @Binding var selectedItem: Item?
    let titleForItem: KeyPath<Item, String>
    let iconForItem: (Item) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.footnote.bold())
                .foregroundStyle(AppTheme.mutedInk)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: allTitle, systemImage: "square.grid.2x2", isSelected: selectedItem == nil) {
                        selectedItem = nil
                    }

                    ForEach(items) { item in
                        FilterChip(
                            title: item[keyPath: titleForItem],
                            systemImage: iconForItem(item),
                            isSelected: selectedItem == item
                        ) {
                            selectedItem = item
                        }
                    }
                }
                .padding(.trailing, 8)
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.mutedInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isSelected ? AppTheme.accent : AppTheme.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
