import SwiftUI

struct ExerciseFilterView: View {
    @Binding var selectedMuscle: MuscleGroup?
    @Binding var selectedEquipment: Equipment?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FilterRow(
                title: "部位",
                allTitle: "すべて",
                items: MuscleGroup.selectionCases,
                selectedItem: $selectedMuscle,
                titleForItem: \.displayName
            )

            FilterRow(
                title: "手法",
                allTitle: "すべて",
                items: Equipment.allCases,
                selectedItem: $selectedEquipment,
                titleForItem: \.displayName
            )
        }
        .padding(.vertical, 4)
    }
}

private struct FilterRow<Item: Identifiable & Hashable>: View {
    let title: String
    let allTitle: String
    let items: [Item]
    @Binding var selectedItem: Item?
    let titleForItem: KeyPath<Item, String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.mutedInk)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: allTitle, isSelected: selectedItem == nil) {
                        selectedItem = nil
                    }

                    ForEach(items) { item in
                        FilterChip(title: item[keyPath: titleForItem], isSelected: selectedItem == item) {
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
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? AppTheme.onAccent : AppTheme.mutedInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isSelected ? AppTheme.accent : AppTheme.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
