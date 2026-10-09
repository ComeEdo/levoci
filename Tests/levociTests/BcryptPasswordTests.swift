import Testing
import VaporTesting

/// Verifica il limite di 72 byte di Bcrypt: i byte oltre il 72° non influenzano l'hash.
/// Sono test puri (nessun DB né Application), quindi veloci.
/// Costo 4 per velocità: il troncamento non dipende dal costo.
@Suite("Bcrypt Password Tests")
struct BcryptPasswordTests {

    @Test("Bcrypt ignora i byte oltre il 72°")
    func bcryptIgnoresBytesBeyond72() throws {
        let first72 = String(repeating: "a", count: 72)
        let passwordX = first72 + "X"   // 73 byte
        let passwordY = first72 + "Y"   // diversa dalla precedente solo dopo il 72° byte
        #expect(passwordX.utf8.count == 73)
        #expect(passwordX != passwordY)

        let hash = try Bcrypt.hash(passwordX, cost: 4)

        // Password diversa oltre il 72° byte -> viene accettata comunque
        #expect(try Bcrypt.verify(passwordY, created: hash))
        // Anche i soli primi 72 byte sono sufficienti
        #expect(try Bcrypt.verify(first72, created: hash))
    }

    @Test("Bcrypt rileva le differenze entro i primi 72 byte")
    func bcryptDetectsDifferencesWithin72Bytes() throws {
        let hash = try Bcrypt.hash(String(repeating: "a", count: 72) + "X", cost: 4)

        // Differenza sul 72° byte (l'ultimo considerato) -> rifiutata
        let differsAtByte72 = String(repeating: "a", count: 71) + "b" + "X"
        #expect(try !Bcrypt.verify(differsAtByte72, created: hash))

        // Differenza sul 1° byte -> rifiutata
        let differsAtByte1 = "b" + String(repeating: "a", count: 71) + "X"
        #expect(try !Bcrypt.verify(differsAtByte1, created: hash))
    }

    @Test("Il limite di Bcrypt è in byte, non in caratteri")
    func bcryptLimitIsInBytesNotCharacters() throws {
        // "è" (U+00E8) occupa 2 byte in UTF-8: 36 caratteri = 72 byte
        let accented = String(repeating: "\u{00E8}", count: 36)
        let passwordX = accented + "X"   // 37 caratteri, ben sotto il limite di 128 di validatePassword
        let passwordY = accented + "Y"
        #expect(accented.utf8.count == 72)
        #expect(passwordX.count == 37)

        let hash = try Bcrypt.hash(passwordX, cost: 4)

        // Con soli 37 caratteri l'ultimo è già ignorato da Bcrypt
        #expect(try Bcrypt.verify(passwordY, created: hash))
    }

    @Test("Bcrypt è salato: lo stesso testo produce hash diversi, quindi gli hash non si confrontano con ==")
    func bcryptHashesOfSamePasswordDiffer() throws {
        let password = "StessaPassword123!"
        let hashA = try Bcrypt.hash(password, cost: 4)
        let hashB = try Bcrypt.hash(password, cost: 4)

        // Stessa password, hash diversi (il salt è casuale a ogni chiamata)...
        #expect(hashA != hashB)
        // ...ma entrambi si verificano correttamente contro la password in chiaro.
        #expect(try Bcrypt.verify(password, created: hashA))
        #expect(try Bcrypt.verify(password, created: hashB))
    }
}
