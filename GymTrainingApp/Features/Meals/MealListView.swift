import PhotosUI
import SwiftUI

struct MealListView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isShowingEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        MetricPill(title: "今日の食事", value: "\(appStore.mealEntries().count)", systemImage: "fork.knife", tint: AppTheme.orange)
                        MetricPill(title: "摂取 kcal", value: AppFormatters.calories(todayCalories), systemImage: "flame", tint: AppTheme.accent)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                Section("記録") {
                    if appStore.mealEntries.isEmpty {
                        Text("食事記録はまだありません")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 18)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    ForEach(appStore.mealEntries) { meal in
                        MealRow(meal: meal)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: appStore.deleteMealEntries)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(TrainingBackground())
            .navigationTitle("食事")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("食事を追加")
                    .accessibilityIdentifier("addMealButton")
                }
            }
            .sheet(isPresented: $isShowingEditor) {
                MealEditorView {
                    isShowingEditor = false
                }
            }
        }
    }

    private var todayCalories: Double {
        appStore.mealEntries().reduce(0) { $0 + $1.calories }
    }
}

private struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        CardContainer {
            HStack(spacing: 12) {
                MealThumbnail(imageData: meal.imageData)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(meal.name)
                            .font(.headline)
                        Spacer()
                        Text(meal.mealType.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.orange)
                    }

                    Text(AppFormatters.shortDateTime.string(from: meal.recordedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(AppFormatters.calories(meal.calories))
                        Text("P \(AppFormatters.grams(meal.protein))")
                        Text("F \(AppFormatters.grams(meal.fat))")
                        Text("C \(AppFormatters.grams(meal.carbs))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("mealRow-\(meal.name)")
    }
}

private struct MealThumbnail: View {
    let imageData: Data?

    var body: some View {
        Group {
            if let imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "fork.knife")
                    .font(.title2)
                    .foregroundStyle(AppTheme.orange)
            }
        }
        .frame(width: 54, height: 54)
        .background(AppTheme.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }
}

private struct MealEditorView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    let onSave: () -> Void

    @State private var mealType: MealType = .lunch
    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    @State private var memo = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section("写真") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("写真を選択・変更", systemImage: "photo")
                    }
                    .accessibilityIdentifier("mealPhotoPicker")

                    if let imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                    }
                }

                Section("食事") {
                    Picker("種類", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    TextField("食事名", text: $name)
                        .accessibilityIdentifier("mealNameField")
                }

                Section("PFC") {
                    TextField("カロリー kcal", text: $calories)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("mealCaloriesField")
                    TextField("たんぱく質 g", text: $protein)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("mealProteinField")
                    TextField("脂質 g", text: $fat)
                        .keyboardType(.decimalPad)
                    TextField("炭水化物 g", text: $carbs)
                        .keyboardType(.decimalPad)
                }

                Section("メモ") {
                    TextField("メモ", text: $memo, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("食事を記録")
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
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveMealButton")
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    imageData = try? await item?.loadTransferable(type: Data.self)
                }
            }
        }
    }

    private func save() {
        appStore.saveMealEntry(
            MealEntry(
                mealType: mealType,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                calories: Double(calories) ?? 0,
                protein: Double(protein) ?? 0,
                fat: Double(fat) ?? 0,
                carbs: Double(carbs) ?? 0,
                memo: memo,
                imageData: imageData
            )
        )
        onSave()
    }
}

#Preview {
    MealListView()
        .environmentObject(AppStore())
}
