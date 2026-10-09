import Vapor

/// Protocollo per il processing e l'archiviazione delle immagini profilo utente
protocol ImageServiceProtocol: Sendable {
    func processAndSaveProfileImage(byteBuffer: ByteBuffer, for userId: UUID) async throws -> UUID
    func deleteProfileImage(for userId: UUID) async throws
    func getProfileImagePath(for userId: UUID) -> String?
}

/// Implementazione del servizio gestione immagini
final class ImageService: ImageServiceProtocol {
    func processAndSaveProfileImage(byteBuffer: ByteBuffer, for userId: UUID) async throws -> UUID {
        // TODO: Ritaglio 1:1 centrato, compressione JPEG e salvataggio sul percorso dedicato
        UUID()
    }

    func deleteProfileImage(for userId: UUID) async throws {
        // TODO: Rimozione sicura del file immagine dal disco
    }

    func getProfileImagePath(for userId: UUID) -> String? {
        // TODO: Verifica esistenza file e restituzione path
        nil
    }
}
