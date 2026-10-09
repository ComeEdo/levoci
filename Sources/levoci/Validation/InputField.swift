import Foundation

/// Campi in input validati dai tipi di `Validation/`.
/// Usato per costruire i messaggi di errore in un solo posto ed evitare stringhe sbagliate tipo "Name" / "name".
/// Il `rawValue` è anche il nome JSON del campo (utile se un domani gli errori indicheranno il campo al client).
enum InputField: String, Sendable, CustomStringConvertible {
    case name
    case surname
    case username
    case email
    case password

    /// Nome leggibile usato nei messaggi di errore (es. "Username").
    var displayName: String { rawValue.capitalized }
    
    var description: String { displayName }
}
