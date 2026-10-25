import Crypto
import Vapor

// MARK: - Implementazione condivisa

protocol PasswordHashable: Sendable {
    func hash(into hasher: AsyncPasswordHasher) async throws -> PasswordHash
    func hashed(on req: Request) async throws -> PasswordHash
}

fileprivate protocol PasswordInput: CustomStringConvertible, CustomDebugStringConvertible {
    func prehashForHashing() -> String
}

extension PasswordInput {
    var description: String { "<redacted>" }
    var debugDescription: String { "<redacted>" }
}

fileprivate func computePasswordPrehash(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return Data(digest).base64EncodedString()
}

// MARK: - Password di Registrazione

/// Password di registrazione già sanificata con `Sanitizer.text` (trim + Unicode NFC)
/// e validata secondo le policy NIST (lunghezza min/max, assenza di caratteri di controllo).
///
/// La password in chiaro è privata: l'unico modo di usarla è `hashed(on:)` o `hash(into:)`, che restituisce un `PasswordHash`.
struct Password: PasswordHashable, PasswordInput {
    /// Lunghezza minima: valore fisso, da cambiare qui quando serve (NIST SP 800-63B consiglia almeno 8).
    fileprivate static let minLength = 2
    fileprivate static let maxLength = 128

    private let plaintext: String

    init(raw: String) throws {
        let sanitized = Sanitizer.text(raw)
        let field = InputField.password

        guard !sanitized.isEmpty else {
            throw APIError.badRequest("The \(field) is required")
        }
        guard sanitized.count >= Self.minLength && sanitized.count <= Self.maxLength else {
            throw APIError.badRequest("The \(field) must be between \(Self.minLength) and \(Self.maxLength) characters long")
        }
        // Rifiuta solo caratteri di controllo (tab, null, ecc.), nessuna altra restrizione sui caratteri
        guard !sanitized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw APIError.badRequest("The \(field) contains invalid control characters")
        }

        self.plaintext = sanitized
    }

    func hash(into hasher: AsyncPasswordHasher) async throws -> PasswordHash {
        PasswordHash(value: try await hasher.hash(computePasswordPrehash(plaintext)))
    }

    func hashed(on req: Request) async throws -> PasswordHash {
        try await hash(into: req.password.async)
    }

    fileprivate func prehashForHashing() -> String {
        computePasswordPrehash(plaintext)
    }
}

// MARK: - Password di Login

/// Password ricevuta durante il login.
/// Sanifica l'input con `Sanitizer.text` (trim + Unicode NFC) e applica la stessa policy
/// di lunghezza della registrazione.
struct LoginPassword: PasswordHashable, PasswordInput {
    private let plaintext: String

    init(raw: String) throws {
        let sanitized = Sanitizer.text(raw)
        let field = InputField.password

        guard !sanitized.isEmpty else {
            throw APIError.badRequest("The \(field) is required")
        }
        guard sanitized.count <= Password.maxLength else {
            throw APIError.badRequest("The \(field) must be at most \(Password.maxLength) characters long")
        }

        self.plaintext = sanitized
    }

    func hash(into hasher: AsyncPasswordHasher) async throws -> PasswordHash {
        PasswordHash(value: try await hasher.hash(computePasswordPrehash(plaintext)))
    }

    func hashed(on req: Request) async throws -> PasswordHash {
        try await hash(into: req.password.async)
    }

    fileprivate func prehashForHashing() -> String {
        computePasswordPrehash(plaintext)
    }
}

// MARK: - PasswordHash

/// Hash della password pronto per il DB (`Credentials.passwordHash`).
///
/// ⚠️ Non è `Equatable` di proposito: bcrypt aggiunge un salt casuale, quindi due hash della stessa password
/// sono DIVERSI e confrontarli con `==` non dice se la password coincide.
/// Per controllare una password si verifica un tipo validato contro l'hash (`Bcrypt.verify`), non hash contro hash.
struct PasswordHash: ValidatedField, Sendable, CustomDebugStringConvertible {
    /// Stringa da salvare sul DB.
    let value: String

    fileprivate init(value: String) {
        self.value = value
    }

    /// Verifica una password contro una stringa hash memorizzata su DB in modo asincrono (senza bloccare l'EventLoop).
    /// Verifica una password di registrazione già validata.
    static func verify(_ password: Password, against storedHash: String, on req: Request) async throws -> Bool {
        try await verifyPassword(password, against: storedHash, on: req)
    }

    /// Verifica una password di login già sanificata.
    static func verify(_ password: LoginPassword, against storedHash: String, on req: Request) async throws -> Bool {
        try await verifyPassword(password, against: storedHash, on: req)
    }

    fileprivate static func verifyPassword(_ password: some PasswordInput, against storedHash: String, on req: Request) async throws -> Bool {
        try await req.password.async.verify(password.prehashForHashing(), created: storedHash)
    }

    /// Evita che l'hash finisca per errore nei log standard o nelle stringhe interpolate.
    var description: String { "<redacted>" }

    /// Evita che l'hash venga ispezionato via debugPrint(), String(reflecting:) o debugger LLDB.
    var debugDescription: String { "<redacted>" }
}

#if DEBUG
extension PasswordHash {
    /// Costruttore dummy riservato ai test per generare un `PasswordHash` senza invocare Bcrypt.
    static func dummy(_ value: String = "dummyHash") -> PasswordHash {
        PasswordHash(value: value)
    }
}
#endif
