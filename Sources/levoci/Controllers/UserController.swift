import Vapor

/// Controller per la gestione del profilo utente e immagini avatar
struct UserController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let userProtected = routes.grouped("user")
        
        userProtected.get("isUserTokenValid", use: isUserTokenValid)
        userProtected.get("refreshUserToken", use: refreshUserToken)
        
        // Gestione Avatar / Profile Image
        userProtected.post("profileImage", use: uploadProfileImage)
        userProtected.delete("profileImage", use: deleteProfileImage)
        userProtected.get(":userUUID", "profileImage", use: getProfileImage)
    }

    @Sendable
    func isUserTokenValid(req: Request) async throws -> Response {
        // TODO: Verifica validità dello UserToken
        throw Abort(.notImplemented)
    }

    @Sendable
    func refreshUserToken(req: Request) async throws -> Response {
        // TODO: Refresh dello UserToken dopo finestra temporale minima
        throw Abort(.notImplemented)
    }

    @Sendable
    func uploadProfileImage(req: Request) async throws -> Response {
        // TODO: Upload immagine, crop 1:1 e salvataggio
        throw Abort(.notImplemented)
    }

    @Sendable
    func deleteProfileImage(req: Request) async throws -> Response {
        // TODO: Rimozione immagine profilo dal filesystem e aggiornamento DB
        throw Abort(.notImplemented)
    }

    @Sendable
    func getProfileImage(req: Request) async throws -> Response {
        // TODO: Download immagine profilo per specifico userUUID
        throw Abort(.notImplemented)
    }
}
