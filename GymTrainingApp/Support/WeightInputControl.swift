import SwiftUI

struct WeightInputControl: View {
    @Binding var weightInKilograms: Double
    let unit: WeightUnit
    let accessibilityIdentifier: String

    @FocusState private var isTextFieldFocused: Bool
    @State private var isWheelPresented = false
    @State private var draftDisplayedWeight = 0.0

    var body: some View {
        HStack(spacing: 4) {
            TextField(
                "重量",
                value: displayedWeight,
                format: .number.precision(.fractionLength(0...1))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
            .focused($isTextFieldFocused)
            .accessibilityLabel("重量")
            .accessibilityIdentifier(accessibilityIdentifier)

            Text(unit.displayName)
                .foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .leading)

            Button {
                isTextFieldFocused = false
                draftDisplayedWeight = displayedWeight.wrappedValue
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
                onCancel: { isWheelPresented = false },
                onSave: {
                    displayedWeight.wrappedValue = draftDisplayedWeight
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
                weightInKilograms = Self.normalized(kilograms)
            }
        )
    }

    private static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(999, max(0, (value * 10).rounded() / 10))
    }
}

private struct WeightWheelPickerSheet: View {
    @Binding var displayedWeight: Double
    let unit: WeightUnit
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("整数", selection: wholePart) {
                    ForEach(0...maximumWholePart, id: \.self) { value in
                        Text("\(value)")
                            .monospacedDigit()
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 116)
                .clipped()
                .accessibilityIdentifier("weightWholePicker")

                Text(".")
                    .font(.title2)
                    .monospacedDigit()

                Picker("小数", selection: tenthsPart) {
                    ForEach(0...9, id: \.self) { value in
                        Text("\(value)")
                            .monospacedDigit()
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 72)
                .clipped()
                .accessibilityIdentifier("weightTenthsPicker")

                Text(unit.displayName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }
            .navigationTitle("重量")
            .navigationBarTitleDisplayMode(.inline)
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

    private var maximumWholePart: Int {
        unit == .kg ? 999 : 2_202
    }

    private var wholePart: Binding<Int> {
        Binding(
            get: { min(maximumWholePart, max(0, Int(displayedWeight.rounded(.down)))) },
            set: { displayedWeight = Double($0) + Double(tenthsPart.wrappedValue) / 10 }
        )
    }

    private var tenthsPart: Binding<Int> {
        Binding(
            get: { max(0, min(9, Int((displayedWeight * 10).rounded()) % 10)) },
            set: { displayedWeight = Double(wholePart.wrappedValue) + Double($0) / 10 }
        )
    }
}

struct RepsInputControl: View {
    @Binding var reps: Int
    let range: ClosedRange<Int>
    let accessibilityIdentifier: String

    @FocusState private var isTextFieldFocused: Bool
    @State private var isWheelPresented = false
    @State private var draftReps = 0

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
            TextField("回数", value: normalizedReps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .textFieldStyle(.roundedBorder)
                .frame(width: 48)
                .focused($isTextFieldFocused)
                .accessibilityLabel("回数")
                .accessibilityIdentifier(accessibilityIdentifier)

            Text("回")
                .foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .leading)

            Button {
                isTextFieldFocused = false
                draftReps = reps
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
    }

    private var normalizedReps: Binding<Int> {
        Binding(
            get: { reps },
            set: { reps = min(range.upperBound, max(range.lowerBound, $0)) }
        )
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
                    .foregroundStyle(.secondary)
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

    var body: some View {
        HStack(spacing: 8) {
            Label("休憩", systemImage: "timer")

            Spacer(minLength: 8)

            TextField("秒数", value: normalizedSeconds, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                .focused($isTextFieldFocused)
                .accessibilityLabel("休憩時間")
                .accessibilityIdentifier("\(accessibilityIdentifier)-field")

            Text("秒")
                .foregroundStyle(.secondary)

            Button {
                isTextFieldFocused = false
                draftSeconds = Self.normalized(seconds)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
    }

    private var normalizedSeconds: Binding<Int> {
        Binding(
            get: { seconds },
            set: { seconds = Self.normalized($0) }
        )
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
                    .foregroundStyle(.secondary)
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

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("整数", selection: wholePart) {
                    ForEach(minimumWholePart...maximumWholePart, id: \.self) { number in
                        Text("\(number)")
                            .monospacedDigit()
                            .tag(number)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 132)
                .clipped()

                if usesTenths {
                    Text(".")
                        .font(.title2)
                        .monospacedDigit()

                    Picker("小数", selection: tenthsPart) {
                        ForEach(0...9, id: \.self) { number in
                            Text("\(number)")
                                .monospacedDigit()
                                .tag(number)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 72)
                    .clipped()
                }

                if !unit.isEmpty {
                    Text(unit)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                }
            }
            .accessibilityIdentifier("numericWheelPicker")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
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

    private var minimumWholePart: Int {
        Int(range.lowerBound.rounded(.down))
    }

    private var maximumWholePart: Int {
        Int(range.upperBound.rounded(.down))
    }

    private var wholePart: Binding<Int> {
        Binding(
            get: { min(maximumWholePart, max(minimumWholePart, Int(value.rounded(.down)))) },
            set: { value = normalized(Double($0) + Double(tenthsPart.wrappedValue) / 10) }
        )
    }

    private var tenthsPart: Binding<Int> {
        Binding(
            get: { max(0, min(9, Int((value * 10).rounded()) % 10)) },
            set: { value = normalized(Double(wholePart.wrappedValue) + Double($0) / 10) }
        )
    }

    private func normalized(_ candidate: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, candidate))
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
