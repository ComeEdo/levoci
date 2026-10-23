import Foundation
import Vapor

/// URL HTTP o HTTPS già sanificato e validato.
/// Conforme a `ValidatedField`, garantisce uno schema http/https, un host valido e normalizza il percorso.
struct HTTPURL: ValidatedField, Equatable, Sendable {
    static let minLength = 8 // Minimo assoluto per 'http://' (7) + 1 carattere di host (es. 'http://a')
    static let maxLength = 2048
    
    /// L'oggetto Foundation URL sottostante.
    let url: URL
    
    /// Valore stringa canonico (sanificato e normalizzato).
    var value: String { url.absoluteString }
    
    var description: String { value }
    
    /// Host dell'URL (garantito non vuoto).
    var host: String { url.host! }
    
    /// Schema dell'URL (garantito "http" o "https").
    var scheme: String { url.scheme!.lowercased() }
    
    /// `true` se l'URL usa HTTPS. Da usare per decidere gli attributi che dipendono dalla connessione sicura
    /// (es. `Secure` sui cookie): dietro Apache l'app vede solo HTTP, ma l'URL pubblico dice come arrivano gli utenti.
    var isSecure: Bool { scheme == "https" }
    
    init(raw: String) throws {
        let clean = Sanitizer.text(raw)
        let field = InputField.url
        
        guard !clean.isEmpty else {
            throw APIError.badRequest("The \(field) is required")
        }
        
        try Self.validateLength(clean, field: field)
        
        guard let parsed = URL(string: clean),
              let scheme = parsed.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = parsed.host, !host.isEmpty else {
            throw APIError.badRequest("The \(field) must be a valid http or https URL with a host")
        }
        
        // Normalizzazione: rimuove eventuale slash finale superfluo dalla root (es. "https://example.com/" -> "https://example.com")
        if clean.hasSuffix("/") && parsed.path == "/" {
            let trimmed = String(clean.dropLast())
            if let normalized = URL(string: trimmed) {
                self.url = normalized
                return
            }
        }
        
        self.url = parsed
    }
    
    /// Costruisce un URL derivato aggiungendo un path e query items in modo sicuro.
    func endpoint(_ path: String, queryItems: [URLQueryItem] = []) -> URL {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let targetURL = url.appendingPathComponent(cleanPath)
        guard !queryItems.isEmpty else { return targetURL }
        var components = URLComponents(url: targetURL, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        return components?.url ?? targetURL
    }
}
