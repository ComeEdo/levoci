import Vapor

/// Controller per l'interrogazione delle classi scolastiche e indirizzi di studio
struct ClassController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let classRoutes = routes.grouped("classes")
        
        classRoutes.get("info", use: getClassInfo)
        classRoutes.get("registration", use: getRegistrationClasses)
    }

    @Sendable
    func getClassInfo(req: Request) async throws -> Response {
        // TODO: Recupero elenco classi attive
        throw Abort(.notImplemented)
    }

    @Sendable
    func getRegistrationClasses(req: Request) async throws -> Response {
        // TODO: Recupero classi disponibili per la registrazione degli studenti
        throw Abort(.notImplemented)
    }
}
