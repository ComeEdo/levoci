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

    @Test("Password: trim e normalizzazione NFC via Sanitizer.text, e non finisce nei log")
    func passwordSanitizationAndLogs() async throws {
        let password = try Password(raw: "  ab  ")
        #expect("\(password)" == "<redacted>")
        #expect(String(reflecting: password) == "<redacted>")

        try await withBcryptApp { app, req in
            let hash = try await password.hashed(on: req)

            // Verifica che anche l'hash sia oscurato nei log
            #expect("\(hash)" == "<redacted>")
            #expect(String(reflecting: hash) == "<redacted>")

            // LoginPassword fa trim con Sanitizer.text, quindi sia "ab" che "  ab  " verificano correttamente l'hash
            let loginClean = try LoginPassword(raw: "ab")
            let loginUntrimmed = try LoginPassword(raw: "  ab  ")
            let loginWrong = try LoginPassword(raw: "cd")

            #expect(try await PasswordHash.verify(loginClean, against: hash.value, on: req))
            #expect(try await PasswordHash.verify(loginUntrimmed, against: hash.value, on: req))
            #expect(try await !PasswordHash.verify(loginWrong, against: hash.value, on: req))
        }
    }

    @Test("Password: con pre-hash SHA-256 supera il limite dei 72 byte di Bcrypt")
    func passwordPrehashExceeds72Bytes() async throws {
        let longPasswordA = String(repeating: "a", count: 72) + "differenza1"
        let longPasswordB = String(repeating: "a", count: 72) + "differenza2"
        let passwordA = try Password(raw: longPasswordA)

        try await withBcryptApp { app, req in
            let hash = try await passwordA.hashed(on: req)
            // Verifica che oltre il 72° byte la password diversa NON venga accettata (risolvendo il troncamento silenzioso di Bcrypt)
            let loginA = try LoginPassword(raw: longPasswordA)
            let loginB = try LoginPassword(raw: longPasswordB)
            #expect(try await PasswordHash.verify(loginA, against: hash.value, on: req))
            #expect(try await !PasswordHash.verify(loginB, against: hash.value, on: req))
        }
    }

    @Test("Password: rifiuta vuota e caratteri di controllo")
    func passwordRejectsEmptyAndControlCharacters() {
        expectBadRequest("The Password is required") { _ = try Password(raw: "") }
        expectBadRequest("The Password is required") { _ = try Password(raw: "   ") }
        expectBadRequest("The Password contains invalid control characters") { _ = try Password(raw: "abc\tdef") }
    }

    // MARK: - LoginPassword

    @Test("LoginPassword: trim, rifiuto vuoto e redaction nei log")
    func loginPasswordFeatures() throws {
        let lp = try LoginPassword(raw: "  secret123  ")
        #expect("\(lp)" == "<redacted>")
        #expect(String(reflecting: lp) == "<redacted>")

        expectBadRequest("The Password is required") { _ = try LoginPassword(raw: "") }
        expectBadRequest("The Password is required") { _ = try LoginPassword(raw: "   ") }
    }

    @Test("Password e LoginPassword: normalizzazione Unicode NFC (NIST SP 800-63B)")
    func unicodeNFCNormalization() async throws {
        // "Jose\u{0301}" (NFD decomposto) vs "José" (NFC precomposto)
        let regNFD = try Password(raw: "Jose\u{0301}")

        try await withBcryptApp { app, req in
            let hash = try await regNFD.hashed(on: req)

            // Login inviato in NFC ("José") deve verificare correttamente l'hash generato da NFD
            let loginNFC = try LoginPassword(raw: "José")
            #expect(try await PasswordHash.verify(loginNFC, against: hash.value, on: req))

            // E viceversa: login inviato in NFD deve verificare l'hash generato da NFD
            let loginNFD = try LoginPassword(raw: "Jose\u{0301}")
            #expect(try await PasswordHash.verify(loginNFD, against: hash.value, on: req))
        }
    }

    // MARK: - SchoolEmail

    @Test("SchoolEmail: normalizza e deduce il ruolo")
    func schoolEmailRole() throws {
        let student = try SchoolEmail(raw: "  Mario.Rossi.STUD@ItisGalileiRoma.it ")
        #expect(student.value == "mario.rossi.stud@itisgalileiroma.it")
        #expect(student.role == .student)

        let teacher = try SchoolEmail(raw: "Mario.Rossi@itisgalileiroma.it")
        #expect(teacher.role == .teacher)
    }

    @Test("SchoolEmail: rifiuta domini e formati non validi")
    func schoolEmailRejections() {
        expectBadRequest("The Email must belong to the @itisgalileiroma.it domain") {
            _ = try SchoolEmail(raw: "mario@gmail.com")
        }
        expectBadRequest("The Email is required") {
            _ = try SchoolEmail(raw: "")
        }
    }

    // MARK: - ValidatedEmail

    @Test("ValidatedEmail: supporta doppi trattini, punycode IDN e caratteri standard RFC 5322")
    func validatedEmailStandardCompliance() throws {
        // GenericEmail concreto per testare la validazione email base senza i vincoli scolastici
        struct GenericEmail: ValidatedEmail {
            let value: String
            init(raw: String) throws {
                let (clean, _, _) = try Self.parseBase(raw)
                self.value = clean
            }
        }

        // Doppi trattini ammessi nel dominio (es. servizi cloud, punycode)
        let hyphenEmail = try GenericEmail(raw: "user@my--domain.com")
        #expect(hyphenEmail.value == "user@my--domain.com")

        // Punycode per domini internazionalizzati (IDN, RFC 3490)
        let punycodeEmail = try GenericEmail(raw: "user@xn--bcher-kva.ch")
        #expect(punycodeEmail.value == "user@xn--bcher-kva.ch")

        // Caratteri speciali ammessi nella parte locale secondo RFC 5322: +, -, _, .
        let taggedEmail = try GenericEmail(raw: "user+mailbox@example.com")
        #expect(taggedEmail.value == "user+mailbox@example.com")

        let underscoreEmail = try GenericEmail(raw: "first_last@example.com")
        #expect(underscoreEmail.value == "first_last@example.com")

        let dottedEmail = try GenericEmail(raw: "first.last@example.com")
        #expect(dottedEmail.value == "first.last@example.com")
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

        expectBadRequest("The Email domain labels cannot start or end with a hyphen") { _ = try GenericEmail(raw: "mario@-domain.com") }
        expectBadRequest("The Email domain labels cannot start or end with a hyphen") { _ = try GenericEmail(raw: "mario@domain-.com") }
        expectBadRequest("The Email domain extension is invalid") { _ = try GenericEmail(raw: "mario@domain.c") }
        expectBadRequest("The Email domain must contain a valid domain extension") { _ = try GenericEmail(raw: "mario@nodomain") }
    }

    @Test("Password: hash(into:) con AsyncPasswordHasher produce un hash verificabile")
    func passwordHashIntoHasher() async throws {
        let password = try Password(raw: "secretPassword123")
        try await withBcryptApp { app, req in
            let hash = try await password.hash(into: app.password.async)
            let validLogin = try LoginPassword(raw: "secretPassword123")
            let wrongLogin = try LoginPassword(raw: "wrongPassword")
            #expect(try await PasswordHash.verify(validLogin, against: hash.value, on: req))
            #expect(try await !PasswordHash.verify(wrongLogin, against: hash.value, on: req))
        }
    }

    // MARK: - JWTToken

    @Test("JWTToken: trim, accetta JWT lunghi come quelli firmati con RSA e non finisce nei log")
    func verificationTokenAccepts() throws {
        // Un JWT RS256 supera i 255 caratteri del limite di default dei campi
        let longToken = "\(String(repeating: "a", count: 40)).\(String(repeating: "b", count: 130)).\(String(repeating: "c", count: 342))"
        #expect(longToken.count > 255)

        let token = try VerificationToken(raw: "  \(longToken)\n")
        #expect(token.value == longToken)
        #expect("\(token)" == "<redacted>")
    }

    @Test("JWTToken: rifiuta vuoto e rispetta i limiti di lunghezza")
    func verificationTokenRejections() {
        expectBadRequest("The Token is required") { _ = try VerificationToken(raw: "   ") }
        expectBadRequest("The Token must be between 10 and 2048 characters long") { _ = try VerificationToken(raw: "a.b.c") }
        expectBadRequest("The Token must be between 10 and 2048 characters long") {
            _ = try VerificationToken(raw: "a.b." + String(repeating: "c", count: 2048))
        }
    }

    // MARK: - HTTPURL

    @Test("HTTPURL: trim, normalizzazione dello slash finale ed endpoint")
    func httpURLAcceptsAndNormalizes() throws {
        let url1 = try HTTPURL(raw: "  https://api.levoci.it/  \n")
        #expect(url1.value == "https://api.levoci.it")
        #expect(url1.host == "api.levoci.it")
        #expect(url1.scheme == "https")
        #expect(url1.isSecure)
        #expect("\(url1)" == "https://api.levoci.it")
        
        let url2 = try HTTPURL(raw: "http://localhost:8080")
        #expect(url2.value == "http://localhost:8080")
        #expect(url2.host == "localhost")
        #expect(url2.scheme == "http")
        #expect(!url2.isSecure)
        
        // Lo schema è case-insensitive: HTTPS maiuscolo è comunque sicuro
        #expect(try HTTPURL(raw: "HTTPS://api.levoci.it").isSecure)
        
        // Creazione endpoint con query items
        let endpoint = url1.endpoint("verify", queryItems: [URLQueryItem(name: "token", value: "abc")])
        #expect(endpoint.absoluteString == "https://api.levoci.it/verify?token=abc")

        // Anche se il path inizia con uno slash, non si crea doppio slash
        let endpointWithSlash = url1.endpoint("/verify", queryItems: [URLQueryItem(name: "token", value: "abc")])
        #expect(endpointWithSlash.absoluteString == "https://api.levoci.it/verify?token=abc")
    }

    @Test("HTTPURL: rispetta i limiti di lunghezza (minimo 8 caratteri per http://a e 9 per https://a, massimo 2048)")
    func httpURLLengthLimits() throws {
        // Minimo per http: 8 caratteri ("http://a") -> valido
        let httpMin = try HTTPURL(raw: "http://a")
        #expect(httpMin.value.count == 8)
        #expect(httpMin.value == "http://a")
        #expect(httpMin.host == "a")

        // Minimo per https: 9 caratteri ("https://a") -> valido
        let httpsMin = try HTTPURL(raw: "https://a")
        #expect(httpsMin.value.count == 9)
        #expect(httpsMin.value == "https://a")
        #expect(httpsMin.host == "a")

        // Sotto il minimo assoluto: 7 caratteri ("http://") -> rifiutato con messaggio sui limiti
        expectBadRequest("The URL must be between 8 and 2048 characters long") {
            _ = try HTTPURL(raw: "http://")
        }

        // 8 caratteri con https ("https://") supera il limite lunghezza (8 >= 8), ma viene rifiutato per host mancante
        expectBadRequest("The URL must be a valid http or https URL with a host") {
            _ = try HTTPURL(raw: "https://")
        }

        // Massimo consentito: 2048 caratteri -> valido
        let maxUrlString = "http://a.b/" + String(repeating: "x", count: 2048 - 11)
        #expect(maxUrlString.count == 2048)
        let maxUrl = try HTTPURL(raw: maxUrlString)
        #expect(maxUrl.value.count == 2048)

        // Oltre il limite massimo (2049 caratteri) -> rifiutato
        let tooLongUrl = maxUrlString + "x"
        #expect(tooLongUrl.count == 2049)
        expectBadRequest("The URL must be between 8 and 2048 characters long") {
            _ = try HTTPURL(raw: tooLongUrl)
        }
    }

    @Test("HTTPURL: rifiuta vuoto, schemi non consentiti e URL senza host")
    func httpURLRejections() {
        expectBadRequest("The URL is required") { _ = try HTTPURL(raw: "   ") }
        expectBadRequest("The URL must be between 8 and 2048 characters long") { _ = try HTTPURL(raw: "http://") }
        expectBadRequest("The URL must be a valid http or https URL with a host") { _ = try HTTPURL(raw: "https://") }
        expectBadRequest("The URL must be a valid http or https URL with a host") { _ = try HTTPURL(raw: "ftp://example.com") }
        expectBadRequest("The URL must be a valid http or https URL with a host") { _ = try HTTPURL(raw: "file:///etc/passwd") }
        expectBadRequest("The URL must be a valid http or https URL with a host") { _ = try HTTPURL(raw: "javascript:alert(1)") }
        expectBadRequest("The URL must be a valid http or https URL with a host") { _ = try HTTPURL(raw: "not-a-valid-url") }
    }
}
