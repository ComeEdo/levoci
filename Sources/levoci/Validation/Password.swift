import Crypto
import Vapor

/// Password di registrazione già validata (policy applicata).
/// Non viene mai modificata (niente trim né normalizzazione). Per il login NON usare questo tipo:
/// al login non si applica la policy, così le password create con regole precedenti restano valide.
///
/// La password in chiaro è privata: l'unico modo di usarla è `hashed(on:)`, che restituisce un `PasswordHash`.
struct Password: Sendable, CustomStringConvertible {
    /// Lunghezza minima: valore fisso, da cambiare qui quando serve (NIST SP 800-63B consiglia almeno 8).
    static let minLength = 2
    static let maxLength = 128

    private let plaintext: String

    init(raw: String) throws {
        let field = InputField.password

        guard !raw.isEmpty else {
            throw APIError.badRequest("The \(field) is required")
        }
        guard raw.count >= Self.minLength && raw.count <= Self.maxLength else {
            throw APIError.badRequest("The \(field) must be between \(Self.minLength) and \(Self.maxLength) characters long")
        }
        // Rifiuta solo caratteri di controllo (tab, null, ecc.), nessuna altra restrizione sui caratteri
        guard !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw APIError.badRequest("The \(field) contains invalid control characters")
        }

        self.plaintext = raw
    }

    /// Calcola il pre-hash SHA-256 della password in chiaro in Base64 (lunghezza fissa 44 caratteri, sempre < 72 byte).
    /// Risolve il limite strutturale dei 72 byte di Bcrypt evitando troncamenti silenti su passphrase lunghe.
    fileprivate static func prehash(_ plaintext: String) -> String {
        let digest = SHA256.hash(data: Data(plaintext.utf8))
        return Data(digest).base64EncodedString()
    }

    /// Hasha la password (pre-hash SHA-256 + Bcrypt) usando un'istanza di `AsyncPasswordHasher`.
    func hash(into hasher: AsyncPasswordHasher) async throws -> PasswordHash {
        let prehashed = Self.prehash(plaintext)
        return PasswordHash(value: try await hasher.hash(prehashed))
    }

    /// Hasha la password (pre-hash SHA-256 + Bcrypt con salt casuale) con l'hasher configurato nella Request.
    func hashed(on req: Request) async throws -> PasswordHash {
        try await hash(into: req.password.async)
    }

    /// Evita che la password finisca per errore in log o stringhe interpolate.
    var description: String { "<redacted>" }
}

/// Hash della password pronto per il DB (`Credentials.passwordHash`).
///
/// ⚠️ Non è `Equatable` di proposito: bcrypt aggiunge un salt casuale, quindi due hash della stessa password
/// sono DIVERSI e confrontarli con `==` non dice se la password coincide.
/// Per controllare una password si verifica il testo in chiaro contro l'hash (`Bcrypt.verify`), non hash contro hash.
struct PasswordHash: ValidatedField, Sendable {
    /// Stringa da salvare sul DB.
    let value: String

    fileprivate init(value: String) {
        self.value = value
    }

    /// Verifica una password in chiaro contro questo hash (applica pre-hash SHA-256 e confronta con Bcrypt).
    func verify(_ plaintext: String) throws -> Bool {
        try Self.verify(plaintext, against: self.value)
    }

    /// Verifica una password in chiaro contro una stringa hash memorizzata su DB (es. `Credentials.passwordHash`).
    static func verify(_ plaintext: String, against storedHash: String) throws -> Bool {
        let prehashed = Password.prehash(plaintext)
        return try Bcrypt.verify(prehashed, created: storedHash)
    }
}

#if DEBUG
extension PasswordHash {
    /// Costruttore dummy riservato ai test per generare un `PasswordHash` senza invocare Bcrypt.
    static func dummy(_ value: String = "dummyHash") -> PasswordHash {
        PasswordHash(value: value)
    }
}
#endif
