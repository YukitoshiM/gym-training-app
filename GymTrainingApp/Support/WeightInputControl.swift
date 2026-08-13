import SwiftUI

struct WeightInputControl: View {
    @Binding var weightInKilograms: Double
    let unit: WeightUnit
    let kilogramRange: ClosedRange<Double>
    let accessibilityIdentifier: String

    @FocusState private var isTextFieldFocused: Bool
    @State private var isWheelPresented = false
    @State private var draftDisplayedWeight = 0.0
    @State private var editText = ""
    @State private var valueBeforeEditing = 0.0

    init(
        weightInKilograms: Binding<Double>,
        unit: WeightUnit,
        kilogramRange: ClosedRange<Double> = 0...999,
        accessibilityIdentifier: String
    ) {
        _weightInKilograms = weightInKilograms
        self.unit = unit
        self.kilogramRange = kilogramRange
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("重量", text: $editText)
            .keyboardType(kilogramRange.lowerBound < 0 ? .numbersAndPunctuation : .decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
            .focused($isTextFieldFocused)
            .accessibilityLabel("重量")
            .accessibilityIdentifier(accessibilityIdentifier)

            Text(unit.displayName)
                .foregroundStyle(AppTheme.mutedInk)
                .frame(minWidth: 20, alignment: .leading)

            Button {
                isTextFieldFocused = false
                let currentValue = displayedWeight.wrappedValue
                draftDisplayedWeight = currentValue != 0 || kilogramRange.lowerBound < 0
                    ? currentValue
                    : defaultDisplayedWeight
                isWheelPresented = true
            } label: {
                Image(systemName: "dial.medium")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("重量をリールで設定")
            .accessibilityIdentifier("wheel-\(accessibilityIdentifier)")
        }
        .sheet(isPresented: $isWheelPresented) {
                WeightWheelPickerSheet(
                    displayedWeight: $draftDisplayedWeight,
                    unit: unit,
                    kilogramRange: kilogramRange,
                    onCancel: { isWheelPresented = false },
                    onSave: {
                        displayedWeight.wrappedValue = draftDisplayedWeight
                        editText = Self.formatted(draftDisplayedWeight)
                        isWheelPresented = false
                    }
                )
            .presentationDetents([.height(330)])
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isTextFieldFocused {
                    Spacer()
                    Button("入力完了") {
                        isTextFieldFocused = false
                    }
                    .accessibilityIdentifier("dismiss-\(accessibilityIdentifier)")
                }
            }
        }
        .onAppear {
            editText = Self.formatted(displayedWeight.wrappedValue)
        }
        .onChange(of: displayedWeight.wrappedValue) { _, value in
            guard !isTextFieldFocused else { return }
            editText = Self.formatted(value)
        }
        .onChange(of: editText) { _, value in
            guard isTextFieldFocused else {
                return
            }
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                displayedWeight.wrappedValue = valueBeforeEditing
                return
            }
            guard let parsedValue = parsed(value) else { return }
            displayedWeight.wrappedValue = parsedValue
        }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if isFocused {
                valueBeforeEditing = displayedWeight.wrappedValue
                editText = ""
            } else {
                commitManualEntry()
            }
        }
    }

    private var displayedWeight: Binding<Double> {
        Binding(
            get: {
                switch unit {
                case .kg: weightInKilograms
                case .lb: weightInKilograms * 2.2046226218
                }
            },
            set: { value in
                let kilograms: Double
                switch unit {
                case .kg:
                    kilograms = value
                case .lb:
                    kilograms = value / 2.2046226218
                }
                weightInKilograms = normalized(kilograms)
            }
        )
    }

    private var defaultDisplayedWeight: Double {
        switch unit {
        case .kg:
            normalized(50)
        case .lb:
            normalized(50) * 2.2046226218
        }
    }

    private func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return kilogramRange.lowerBound }
        let rounded = (value * 10).rounded() / 10
        return min(kilogramRange.upperBound, max(kilogramRange.lowerBound, rounded))
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func commitManualEntry() {
        guard let value = parsed(editText) else {
            displayedWeight.wrappedValue = valueBeforeEditing
            editText = Self.formatted(valueBeforeEditing)
            return
        }
        displayedWeight.wrappedValue = value
        editText = Self.formatted(displayedWeight.wrappedValue)
    }

    private func parsed(_ text: String) -> Double? {
        let normalizedText = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalizedText), value.isFinite else {
            return nil
        }
        return value
    }
}

private struct WeightWheelPickerSheet: View {
    @Binding var displayedWeight: Double
    let unit: WeightUnit
    let kilogramRange: ClosedRange<Double>
    let onCancel: () -> Void
    let onSave: () -> Void
    @State private var initialStepIndex: Int?

    init(
        displayedWeight: Binding<Double>,
        unit: WeightUnit,
        kilogramRange: ClosedRange<Double>,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        _displayedWeight = displayedWeight
        self.unit = unit
        self.kilogramRange = kilogramRange
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("重量", selection: stepIndex) {
                    ForEach(availableStepRange, id: \.self) { index in
                        Text(Self.formatted(Double(index) / 10))
                            .monospacedDigit()
                            .tag(index)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 170)
                .clipped()
                .accessibilityIdentifier("weightPicker")

                Text(unit.displayName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(width: 44, alignment: .leading)
            }
            .navigationTitle("重量")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                initialStepIndex = currentStepIndex
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("設定", action: onSave)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("saveWeightWheelButton")
                }
            }
        }
    }

    private var displayedStepRange: ClosedRange<Int> {
        let conversion = unit == .kg ? 1.0 : 2.2046226218
        let lowerBound = Int((kilogramRange.lowerBound * conversion * 10).rounded(.up))
        let upperBound = Int((kilogramRange.upperBound * conversion * 10).rounded(.down))
        return lowerBound...upperBound
    }

    private var currentStepIndex: Int {
        min(
            displayedStepRange.upperBound,
            max(displayedStepRange.lowerBound, Int((displayedWeight * 10).rounded()))
        )
    }

    private var availableStepRange: ClosedRange<Int> {
        let center = initialStepIndex ?? currentStepIndex
        let lowerBound = max(displayedStepRange.lowerBound, center - 200)
        let upperBound = min(displayedStepRange.upperBound, center + 200)
        return lowerBound...upperBound
    }

    private var stepIndex: Binding<Int> {
        Binding(
            get: {
                min(
                    displayedStepRange.upperBound,
                    max(displayedStepRange.lowerBound, Int((displayedWeight * 10).rounded()))
                )
            },
            set: { displayedWeight = Double($0) / 10 }
        )
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

struct RepsInputControl: View {
    @Binding var reps: Int
    let range: ClosedRange<Int>
    let accessibilityIdentifier: String

    @FocusState private var isTextFieldFocused: Bool
    @State private var isWheelPresented = false
    @State private var draftReps = 0
    @State private var editText = ""
    @State private var valueBeforeEditing = 0

    init(
        reps: Binding<Int>,
        in range: ClosedRange<Int> = 0...999,
        accessibilityIdentifier: String
    ) {
        _reps = reps
        self.range = range
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("回数", text: $editText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .focused($isTextFieldFocused)
                .accessibilityLabel("回数")
                .accessibilityIdentifier(accessibilityIdentifier)

            Text("回")
                .foregroundStyle(AppTheme.mutedInk)
                .frame(minWidth: 20, alignment: .leading)

            Button {
                isTextFieldFocused = false
                draftReps = reps > 0
                    ? reps
                    : min(range.upperBound, max(range.lowerBound, 10))
                isWheelPresented = true
            } label: {
                Image(systemName: "dial.medium")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("回数をリールで設定")
            .accessibilityIdentifier("wheel-\(accessibilityIdentifier)")
        }
        .sheet(isPresented: $isWheelPresented) {
            RepsWheelPickerSheet(
                reps: $draftReps,
                range: range,
                onCancel: { isWheelPresented = false },
                onSave: {
                    reps = draftReps
                    editText = String(reps)
                    isWheelPresented = false
                }
            )
            .presentationDetents([.height(330)])
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isTextFieldFocused {
                    Spacer()
                    Button("入力完了") {
                        isTextFieldFocused = false
                    }
                    .accessibilityIdentifier("dismiss-\(accessibilityIdentifier)")
                }
            }
        }
        .onAppear {
            editText = String(reps)
        }
        .onChange(of: reps) { _, value in
            guard !isTextFieldFocused else { return }
            editText = String(value)
        }
        .onChange(of: editText) { _, value in
            guard isTextFieldFocused else { return }
            if value.isEmpty {
                reps = valueBeforeEditing
            } else if let parsed = Int(value) {
                reps = min(range.upperBound, max(range.lowerBound, parsed))
            }
        }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if isFocused {
                valueBeforeEditing = reps
                editText = ""
            } else if let value = Int(editText) {
                reps = min(range.upperBound, max(range.lowerBound, value))
                editText = String(reps)
            } else {
                reps = valueBeforeEditing
                editText = String(valueBeforeEditing)
            }
        }
    }
}

private struct RepsWheelPickerSheet: View {
    @Binding var reps: Int
    let range: ClosedRange<Int>
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("回数", selection: $reps) {
                    ForEach(range, id: \.self) { value in
                        Text("\(value)")
                            .monospacedDigit()
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 140)
                .clipped()
                .accessibilityIdentifier("repsPicker")

                Text("回")
                    .font(.headline)
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(width: 44, alignment: .leading)
            }
            .navigationTitle("回数")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("設定", action: onSave)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("saveRepsWheelButton")
                }
            }
        }
    }
}

struct RestSecondsInputControl: View {
    @Binding var seconds: Int
    let accessibilityIdentifier: String

    @State private var isWheelPresented = false
    @State private var draftSeconds = 90
    @FocusState private var isTextFieldFocused: Bool
    @State private var editText = ""
    @State private var valueBeforeEditing = 90

    var body: some View {
        HStack(spacing: 8) {
            Label("休憩", systemImage: "timer")

            Spacer(minLength: 8)

            TextField("秒数", text: $editText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                .focused($isTextFieldFocused)
                .accessibilityLabel("休憩時間")
                .accessibilityIdentifier("\(accessibilityIdentifier)-field")

            Text("秒")
                .foregroundStyle(AppTheme.mutedInk)

            Button {
                isTextFieldFocused = false
                draftSeconds = seconds > 0 ? Self.normalized(seconds) : 90
                isWheelPresented = true
            } label: {
                Image(systemName: "dial.medium")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("休憩時間をリールで設定")
            .accessibilityIdentifier(accessibilityIdentifier)
        }
        .sheet(isPresented: $isWheelPresented) {
            NavigationStack {
                HStack(spacing: 0) {
                    Picker("休憩時間", selection: $draftSeconds) {
                        ForEach(Array(stride(from: 0, through: 600, by: 5)), id: \.self) { value in
                            Text(Self.formatted(value))
                                .monospacedDigit()
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 150)
                    .clipped()
                    .accessibilityIdentifier("restSecondsPicker")

                    Text("分:秒")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .frame(width: 52, alignment: .leading)
                }
                .navigationTitle("休憩時間")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            isWheelPresented = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("設定") {
                            seconds = draftSeconds
                            editText = String(seconds)
                            isWheelPresented = false
                        }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("saveRestSecondsButton")
                    }
                }
            }
            .presentationDetents([.height(330)])
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isTextFieldFocused {
                    Spacer()
                    Button("入力完了") {
                        isTextFieldFocused = false
                    }
                    .accessibilityIdentifier("dismiss-\(accessibilityIdentifier)-field")
                }
            }
        }
        .onAppear {
            editText = String(seconds)
        }
        .onChange(of: seconds) { _, value in
            guard !isTextFieldFocused else { return }
            editText = String(value)
        }
        .onChange(of: editText) { _, value in
            guard isTextFieldFocused else { return }
            if value.isEmpty {
                seconds = valueBeforeEditing
            } else if let parsed = Int(value) {
                seconds = Self.normalized(parsed)
            }
        }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if isFocused {
                valueBeforeEditing = seconds
                editText = ""
            } else if let value = Int(editText) {
                seconds = Self.normalized(value)
                editText = String(seconds)
            } else {
                seconds = valueBeforeEditing
                editText = String(valueBeforeEditing)
            }
        }
    }

    private static func normalized(_ seconds: Int) -> Int {
        min(600, max(0, Int((Double(seconds) / 5).rounded()) * 5))
    }

    private static func formatted(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

struct NumericTextInputControl: View {
    @Binding var text: String
    let title: String
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double
    let accessibilityIdentifier: String

    @FocusState private var isTextFieldFocused: Bool
    @State private var isWheelPresented = false
    @State private var draftValue = 0.0
    @State private var textBeforeEditing = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(title)

            Spacer(minLength: 8)

            TextField(title, text: $text)
                .keyboardType(step < 1 ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 88)
                .focused($isTextFieldFocused)
                .accessibilityLabel(title)
                .accessibilityIdentifier(accessibilityIdentifier)

            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(minWidth: 28, alignment: .leading)
            }

            Button {
                isTextFieldFocused = false
                draftValue = normalized(parsedValue ?? defaultValue)
                isWheelPresented = true
            } label: {
                Image(systemName: "dial.medium")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(title)をリールで設定")
            .accessibilityIdentifier("wheel-\(accessibilityIdentifier)")
        }
        .sheet(isPresented: $isWheelPresented) {
            NumericWheelPickerSheet(
                value: $draftValue,
                title: title,
                unit: unit,
                range: range,
                usesTenths: step < 1,
                onCancel: { isWheelPresented = false },
                onSave: {
                    text = formatted(draftValue)
                    isWheelPresented = false
                }
            )
            .presentationDetents([.height(330)])
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isTextFieldFocused {
                    Spacer()
                    Button("入力完了") {
                        isTextFieldFocused = false
                    }
                    .accessibilityIdentifier("dismiss-\(accessibilityIdentifier)")
                }
            }
        }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if isFocused {
                textBeforeEditing = text
                text = ""
            } else if let parsedValue {
                text = formatted(normalized(parsedValue))
            } else {
                text = textBeforeEditing
            }
        }
    }

    private var parsedValue: Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        let stepped = (value / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, stepped))
    }

    private func formatted(_ value: Double) -> String {
        if step < 1 {
            return value.formatted(.number.precision(.fractionLength(0...1)))
        }
        return String(Int(value.rounded()))
    }
}

private struct NumericWheelPickerSheet: View {
    @Binding var value: Double
    let title: String
    let unit: String
    let range: ClosedRange<Double>
    let usesTenths: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    @State private var initialStepIndex: Int?

    init(
        value: Binding<Double>,
        title: String,
        unit: String,
        range: ClosedRange<Double>,
        usesTenths: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        _value = value
        self.title = title
        self.unit = unit
        self.range = range
        self.usesTenths = usesTenths
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker(title, selection: stepIndex) {
                    ForEach(availableStepRange, id: \.self) { index in
                        Text(formattedValue(for: index))
                            .monospacedDigit()
                            .tag(index)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 180)
                .clipped()
                .accessibilityIdentifier("numericWheelPicker")

                if !unit.isEmpty {
                    Text(unit)
                        .font(.headline)
                        .foregroundStyle(AppTheme.mutedInk)
                        .frame(width: 52, alignment: .leading)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                initialStepIndex = currentStepIndex
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("設定", action: onSave)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("saveNumericWheelButton")
                }
            }
        }
    }

    private var multiplier: Double {
        usesTenths ? 10 : 1
    }

    private var minimumStepIndex: Int {
        Int((range.lowerBound * multiplier).rounded())
    }

    private var maximumStepIndex: Int {
        Int((range.upperBound * multiplier).rounded())
    }

    private var currentStepIndex: Int {
        min(maximumStepIndex, max(minimumStepIndex, Int((value * multiplier).rounded())))
    }

    private var availableStepRange: ClosedRange<Int> {
        let center = initialStepIndex ?? currentStepIndex
        return max(minimumStepIndex, center - 200)...min(maximumStepIndex, center + 200)
    }

    private var stepIndex: Binding<Int> {
        Binding(
            get: { min(maximumStepIndex, max(minimumStepIndex, Int((value * multiplier).rounded()))) },
            set: { value = Double($0) / multiplier }
        )
    }

    private func formattedValue(for index: Int) -> String {
        let value = Double(index) / multiplier
        if usesTenths {
            return value.formatted(.number.precision(.fractionLength(1)))
        }
        return String(Int(value.rounded()))
    }
}

extension BodyMetricKind {
    var inputRange: ClosedRange<Double> {
        switch self {
        case .bodyWeight: 0...500
        case .waist: 0...300
        case .bodyFatPercentage: 0...100
        }
    }

    var defaultInputValue: Double {
        switch self {
        case .bodyWeight: 60
        case .waist: 80
        case .bodyFatPercentage: 20
        }
    }
}
