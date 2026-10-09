import Foundation

/// Trasformazioni pure di sanificazione, condivise da tutti i tipi validati (`Validation/`).
/// Qui NON ci sono regole di validazione: solo pulizia dell'input.
enum Sanitizer {
    /// Trim di spazi e newline + normalizzazione Unicode NFC
    /// (accenti scomposti `e` + `´` → carattere precomposto `é`).
    static func text(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    /// Come `text`, in più normalizza gli apostrofi curvi (‘ ’) in apostrofo dritto (').
    static func personName(_ input: String) -> String {
        normalizeApostrophes(text(input))
    }

    /// Trim di spazi e newline + lowercase.
    static func email(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Normalizza tutti i tipi di apostrofo curvo (‘, ’) in apostrofo dritto (')
    static func normalizeApostrophes(_ input: String) -> String {
        input.replacingOccurrences(of: "\u{2018}", with: "'").replacingOccurrences(of: "\u{2019}", with: "'")
    }
}
