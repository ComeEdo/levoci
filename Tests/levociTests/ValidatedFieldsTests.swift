import Testing
import Foundation
import VaporTesting
@testable import levoci

/// Test puri sui tipi validati (`Validation/`): nessun DB, nessuna Application.
@Suite("Validated Fields Tests")
struct ValidatedFieldsTests {

    /// Verifica che il blocco lanci un `APIError` con esattamente questo messaggio.
    private func expectBadRequest(
        _ message: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ body: () throws -> Void
    ) {
        do {
            try body()
            Issue.record("Atteso errore \"\(message)\" ma non è stato lanciato nulla", sourceLocation: sourceLocation)
        } catch let error as APIError {
            #expect(error.reason == message, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Errore inatteso: \(error)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - PersonName

    @Test("PersonName: trim, apostrofo curvo e NFC")
    func personNameSanitization() throws {
        let surname = try PersonName(raw: "  D\u{2019}Angelo \n", field: .surname)
        #expect(surname.value == "D'Angelo")

        // "José" con accento scomposto (e + U+0301): 5 scalari. Dopo la NFC devono essere 4.
        // (Il confronto di String in Swift considera uguali le due forme, quindi si contano gli scalari.)
        let name = try PersonName(raw: "Jose\u{0301}", field: .name)
        #expect(name.value.unicodeScalars.count == 4)
    }

    @Test("PersonName: rifiuta valori non validi con il messaggio corretto")
    func personNameRejections() {
        expectBadRequest("The Name contains invalid characters") { _ = try PersonName(raw: "Mario123", field: .name) }
        expectBadRequest("The Surname cannot have repeating spaces") { _ = try PersonName(raw: "De  Luca", field: .surname) }
        expectBadRequest("The Name cannot start or end with an apostrophe") { _ = try PersonName(raw: "'Anna", field: .name) }
        expectBadRequest("The Name contains consecutive apostrophes") { _ = try PersonName(raw: "D''Angelo", field: .name) }
        expectBadRequest("The Name contains isolated apostrophes") { _ = try PersonName(raw: "Mario 'Rossi", field: .name) }
        expectBadRequest("The Name contains isolated apostrophes") { _ = try PersonName(raw: "Mario' Rossi", field: .name) }
        expectBadRequest("The Name is required") { _ = try PersonName(raw: "   ", field: .name) }
        expectBadRequest("The Surname is required") { _ = try PersonName(raw: "", field: .surname) }
    }

    // MARK: - Username

    @Test("Username è case-sensitive e fa il trim")
    func usernameIsCaseSensitive() throws {
        let upper = try Username(raw: "Mario")
        let lower = try Username(raw: "mario")
        #expect(upper.value == "Mario")
        #expect(lower.value == "mario")
        #expect(upper != lower)

        let trimmed = try Username(raw: "  Mario_1 ")
        #expect(trimmed.value == "Mario_1")
    }

    @Test("Username: rifiuta caratteri non ammessi e vuoti")
    func usernameRejections() {
        expectBadRequest("The Username contains invalid characters") { _ = try Username(raw: "mario!") }
        expectBadRequest("The Username contains invalid characters") { _ = try Username(raw: "mario rossi") }
        expectBadRequest("The Username is required") { _ = try Username(raw: "") }
    }

    // MARK: - Password

    @Test("Password: arriva all'hasher invariata (spazi inclusi) e non finisce nei log")
    func passwordIsNeverModified() async throws {
        let password = try Password(raw: "  ab  ")
        #expect("\(password)" == "<redacted>")

        // Hash reale con bcrypt (costo basso per velocità), senza possibilità di leggere il testo in chiaro
        let app = try await Application.make(.testing)
        app.passwords.use(.bcrypt(cost: 4))
        let req = Request(application: app, on: app.eventLoopGroup.next())

        let hash: PasswordHash
        do {
            hash = try await password.hashed(on: req)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()

        // La password con gli spazi originali coincide; la versione "trimmata" no (verifica con pre-hash SHA-256)
        #expect(try hash.verify("  ab  "))
        #expect(try !hash.verify("ab"))
        #expect(try PasswordHash.verify("  ab  ", against: hash.value))
        #expect(try !PasswordHash.verify("ab", against: hash.value))
    }

    @Test("Password: con pre-hash SHA-256 supera il limite dei 72 byte di Bcrypt")
    func passwordPrehashExceeds72Bytes() async throws {
        let longPasswordA = String(repeating: "a", count: 72) + "differenza1"
        let longPasswordB = String(repeating: "a", count: 72) + "differenza2"
        let passwordA = try Password(raw: longPasswordA)

        let app = try await Application.make(.testing)
        app.passwords.use(.bcrypt(cost: 4))
        let req = Request(application: app, on: app.eventLoopGroup.next())

        let hash: PasswordHash
        do {
            hash = try await passwordA.hashed(on: req)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()

        // Verifica che oltre il 72° byte la password diversa NON venga accettata (risolvendo il troncamento silenzioso di Bcrypt)
        #expect(try hash.verify(longPasswordA))
        #expect(try !hash.verify(longPasswordB))
    }

    @Test("Password: rispetta i limiti di lunghezza")
    func passwordLengthLimits() throws {
        #expect(throws: APIError.self) {
            _ = try Password(raw: String(repeating: "a", count: Password.minLength - 1))
        }
        #expect(throws: APIError.self) {
            _ = try Password(raw: String(repeating: "a", count: Password.maxLength + 1))
        }
        _ = try Password(raw: String(repeating: "a", count: Password.minLength))
        _ = try Password(raw: String(repeating: "a", count: Password.maxLength))
    }

    @Test("Password: rifiuta vuota e caratteri di controllo")
    func passwordRejectsEmptyAndControlCharacters() {
        expectBadRequest("The Password is required") { _ = try Password(raw: "") }
        expectBadRequest("The Password contains invalid control characters") { _ = try Password(raw: "abc\tdef") }
    }

    // MARK: - SchoolEmail

    @Test("SchoolEmail: normalizza e deduce il ruolo")
    func schoolEmailRole() throws {
        let student = try SchoolEmail(raw: "  Mario.Rossi.STUD@ItisGalileiRoma.it ")
        #expect(student.value == "mario.rossi.stud@itisgalileiroma.it")
        #expect(student.localPart == "mario.rossi.stud")
        #expect(student.domain == "itisgalileiroma.it")
        #expect(student.description == "mario.rossi.stud@itisgalileiroma.it")
        #expect(student.role == .student)

        let teacher = try SchoolEmail(raw: "mario.rossi@itisgalileiroma.it")
        #expect(teacher.localPart == "mario.rossi")
        #expect(teacher.domain == "itisgalileiroma.it")
        #expect(teacher.role == .teacher)
    }

    @Test("SchoolEmail: rifiuta domini e formati non validi")
    func schoolEmailRejections() {
        expectBadRequest("The Email must belong to the @itisgalileiroma.it domain") { _ = try SchoolEmail(raw: "mario@gmail.com") }
        expectBadRequest("The Email cannot start with '.', '_' or '-'") { _ = try SchoolEmail(raw: ".mario@itisgalileiroma.it") }
        expectBadRequest("The Email contains consecutive special characters") { _ = try SchoolEmail(raw: "ma..rio.stud@itisgalileiroma.it") }
        expectBadRequest("The Email local part contains invalid characters") { _ = try SchoolEmail(raw: "ma rio@itisgalileiroma.it") }
        expectBadRequest("School Email contains invalid characters") { _ = try SchoolEmail(raw: "mario+tag@itisgalileiroma.it") }
        expectBadRequest("The Email is required") { _ = try SchoolEmail(raw: "") }
    }

    // MARK: - ValidatedEmail Base Compliance

    @Test("ValidatedEmail: supporta doppi trattini, punycode IDN e caratteri standard RFC 5322")
    func validatedEmailStandardCompliance() throws {
        struct GenericEmail: ValidatedEmail {
            let value: String
            init(raw: String) throws {
                let (clean, _, _) = try Self.parseBase(raw)
                self.value = clean
            }
        }

        // Supporto Punycode IDN (xn--)
        let idn = try GenericEmail(raw: "mario.rossi@xn--mller-kva.de")
        #expect(idn.domain == "xn--mller-kva.de")

        // Supporto doppio trattino nel dominio e nella parte locale
        let doubleHyphen = try GenericEmail(raw: "foo--bar@my--site.com")
        #expect(doubleHyphen.localPart == "foo--bar")
        #expect(doubleHyphen.domain == "my--site.com")

        // Supporto caratteri standard RFC 5322 / HTML5 (es. '+' per tag o alias)
        let plusTag = try GenericEmail(raw: "mario+newsletter@domain.com")
        #expect(plusTag.localPart == "mario+newsletter")

        // Rifiuto spazi nella localPart
        expectBadRequest("The Email local part contains invalid characters") {
            _ = try GenericEmail(raw: "mario rossi@domain.com")
        }
    }

    @Test("ValidatedEmail: rifiuta domini malformati")
    func validatedEmailDomainRejections() {
        struct GenericEmail: ValidatedEmail {
            let value: String
            init(raw: String) throws {
                let (clean, _, _) = try Self.parseBase(raw)
                self.value = clean
            }
        }

        expectBadRequest("The Email domain cannot contain underscores") { _ = try GenericEmail(raw: "mario@sub_domain.com") }
        expectBadRequest("The Email domain contains consecutive special characters") { _ = try GenericEmail(raw: "mario@domain..com") }
        expectBadRequest("The Email domain labels cannot start or end with a hyphen") { _ = try GenericEmail(raw: "mario@-domain.com") }
        expectBadRequest("The Email domain labels cannot start or end with a hyphen") { _ = try GenericEmail(raw: "mario@domain-.com") }
        expectBadRequest("The Email domain extension is invalid") { _ = try GenericEmail(raw: "mario@domain.c") }
        expectBadRequest("The Email domain must contain a valid domain extension") { _ = try GenericEmail(raw: "mario@nodomain") }
    }

    @Test("Password: hash(into:) con AsyncPasswordHasher produce un hash verificabile")
    func passwordHashIntoHasher() async throws {
        let password = try Password(raw: "secretPassword123")
        let app = try await Application.make(.testing)
        app.passwords.use(.bcrypt(cost: 4))

        let hash: PasswordHash
        do {
            hash = try await password.hash(into: app.password.async)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()

        #expect(try hash.verify("secretPassword123"))
        #expect(try !hash.verify("wrongPassword"))
    }
}
