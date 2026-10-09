import Vapor

/// Controller per la gestione dei post e delle recensioni (feed, voti, delta sync)
struct PostController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let postRoutes = routes.grouped("user", "post")
        
        postRoutes.get(use: getPosts)
        postRoutes.post(use: createPost)
    }

    @Sendable
    func getPosts(req: Request) async throws -> Response {
        // TODO: Recupero post con supporto per sincronizzazione incrementale (?lastSync=...)
        throw Abort(.notImplemented)
    }

    @Sendable
    func createPost(req: Request) async throws -> Response {
        // TODO: Creazione post con voto associato (Docente, Materia, o Ora di lezione)
        throw Abort(.notImplemented)
    }
}
