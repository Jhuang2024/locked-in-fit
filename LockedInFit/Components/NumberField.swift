import SwiftUI
import UIKit

// MARK: - NumberText

/// The string-to-number rules behind `NumberField`, kept free of SwiftUI so
/// they can be tested directly.
///
/// Everything here works in the device's locale: the number pad prints
/// whatever decimal separator the region uses, so that's what gets shown and
/// what gets accepted. A "." or a "," is always accepted regardless, because
/// a hardware keyboard can produce either one.
enum NumberText {
    static var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    /// Filters typed text down to something that can only ever be a number:
    /// digits, at most one decimal separator, and an optional leading minus.
    /// Deliberately permissive about half-finished input — "", "-", "12." and
    /// ".5" all survive, because they're what a field looks like mid-edit.
    static func sanitize(_ raw: String, allowsNegative: Bool = false) -> String {
        var whole = ""
        var fraction: String?
        var isNegative = false

        for (index, character) in raw.enumerated() {
            if character == "-" || character == "\u{2212}" {
                // Only meaningful as the first character; a minus anywhere
                // else is a stray keystroke.
                if allowsNegative, index == 0 { isNegative = true }
                continue
            }
            if character.isNumber, let digit = character.wholeNumberValue, (0...9).contains(digit) {
                // Normalized through `wholeNumberValue` so a non-ASCII digit
                // keyboard (Arabic-Indic, Devanagari…) still lands on 0-9.
                if fraction == nil { whole.append(String(digit)) } else { fraction?.append(String(digit)) }
                continue
            }
            if character == "." || character == "," || String(character) == decimalSeparator, fraction == nil {
                fraction = ""
            }
        }

        // "007" is 7. A lone leading zero stays, so "0" and "0.5" are typeable.
        while whole.count > 1, whole.hasPrefix("0") { whole.removeFirst() }

        var result = isNegative ? "-" : ""
        result += whole
        if let fraction { result += decimalSeparator + fraction }
        return result
    }

    /// The number a field's text currently means, or nil when it doesn't mean
    /// one yet (empty, a lone minus, a lone separator).
    static func parse(_ text: String) -> Double? {
        var normalized = text.replacingOccurrences(of: decimalSeparator, with: ".")
        normalized = normalized.replacingOccurrences(of: ",", with: ".")
        normalized = normalized.replacingOccurrences(of: "\u{2212}", with: "-")
        guard normalized.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == "-") }) else { return nil }
        if normalized.hasSuffix(".") { normalized.removeLast() }
        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        if normalized.hasPrefix("-.") { normalized = "-0" + normalized.dropFirst() }
        guard !normalized.isEmpty, normalized != "-" else { return nil }
        return Double(normalized)
    }

    /// How a value reads when the field isn't being typed in. Zero renders as
    /// an empty string so the placeholder shows through and the first
    /// keystroke doesn't have to clear a "0" first.
    static func display(_ value: Double, fractionDigits: Int = 0) -> String {
        guard value.isFinite else { return "" }
        let places = max(0, fractionDigits)
        var text = String(format: "%.\(places)f", value)
        if places > 0, text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        // Rounding can land on zero from a nonzero value (0.4 g at zero
        // decimal places); either way an empty field reads as nothing logged.
        if text == "0" || text == "-0" { return "" }
        if decimalSeparator != "." { text = text.replacingOccurrences(of: ".", with: decimalSeparator) }
        return text
    }

    /// Doubles typed into an Int-backed field can be far outside Int's range
    /// (a number pad makes 30 digits easy), and `Int(_: Double)` traps on
    /// those rather than saturating.
    static func integer(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded()
        if rounded >= Double(Int.max) { return Int.max }
        if rounded <= Double(Int.min) { return Int.min }
        return Int(rounded)
    }
}

// MARK: - NumberField

/// Text entry for a number that stays editable while you're typing.
///
/// `TextField(_:value:format:)` re-derives its text from the bound value on
/// every keystroke, so the field can never hold a string the format style
/// can't parse. Deleting the last digit of "200" leaves "", which parses to
/// nothing, so the previous text comes straight back: the field bottoms out
/// at "2" and a 200 g portion can't be retyped as 100 g without deleting the
/// whole row and starting over.
///
/// This keeps the typed text as its own state and writes back only while the
/// field has focus, which fixes both halves of that:
/// - a half-typed field ("", "-", "12.") is allowed, and an empty field
///   simply reads as 0 until the next keystroke;
/// - the value never round-trips through the display format behind the user's
///   back, so a stored 175.4 kcal shown as "175" stays 175.4 unless it's
///   actually edited.
struct NumberField: View {
    private let placeholder: String
    @Binding private var value: Double
    private let fractionDigits: Int
    private let allowsNegative: Bool
    private let keyboard: UIKeyboardType
    private let alignment: TextAlignment

    @State private var text = ""
    @FocusState private var focused: Bool

    init(_ placeholder: String = "0",
         value: Binding<Double>,
         fractionDigits: Int = 0,
         allowsNegative: Bool = false,
         keyboard: UIKeyboardType = .decimalPad,
         alignment: TextAlignment = .trailing) {
        self.placeholder = placeholder
        self._value = value
        self.fractionDigits = fractionDigits
        self.allowsNegative = allowsNegative
        self.keyboard = keyboard
        self.alignment = alignment
    }

    /// Int-backed fields (reps, rest seconds) round on the way in.
    init(_ placeholder: String = "0",
         value: Binding<Int>,
         allowsNegative: Bool = false,
         keyboard: UIKeyboardType = .numberPad,
         alignment: TextAlignment = .trailing) {
        self.init(placeholder,
                  value: Binding(get: { Double(value.wrappedValue) },
                                 set: { value.wrappedValue = NumberText.integer($0) }),
                  fractionDigits: 0,
                  allowsNegative: allowsNegative,
                  keyboard: keyboard,
                  alignment: alignment)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboard)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .onAppear { syncTextFromValue() }
            .onChange(of: text) { _, newText in
                // Only the person typing writes to the value. Without this,
                // the text this view sets itself (on appear, or when the
                // value changes elsewhere) would write straight back through
                // the display format and quietly round the stored number.
                guard focused else { return }
                let cleaned = NumberText.sanitize(newText, allowsNegative: allowsNegative)
                guard cleaned == newText else {
                    text = cleaned  // re-enters here with the cleaned string
                    return
                }
                value = NumberText.parse(cleaned) ?? 0
            }
            .onChange(of: value) { _, newValue in
                // A value changed from outside (another field rescaling this
                // one, a preset applied, a fresh row) refreshes the text; a
                // value this field just wrote does not, so what's on screen
                // stays exactly what was typed.
                guard !focused, NumberText.parse(text) != newValue else { return }
                syncTextFromValue()
            }
            .onChange(of: focused) { _, isFocused in
                guard !isFocused else { return }
                syncTextFromValue()
            }
    }

    private func syncTextFromValue() {
        let formatted = NumberText.display(value, fractionDigits: fractionDigits)
        if formatted != text { text = formatted }
    }
}
