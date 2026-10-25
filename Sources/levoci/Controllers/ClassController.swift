import Vapor
import Fluent

/// Controller per l'interrogazione delle classi scolastiche e indirizzi di studio
struct ClassController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let classRoutes = routes.grouped("classes")
        
        classRoutes.get(use: getActiveClasses)
    }

    /// Recupero elenco delle classi attive
    @Sendable
    func getActiveClasses(req: Request) async throws -> [SchoolClassDTO] {
        let now = Date()
        let classes = try await SchoolClass.query(on: req.db)
            .with(\.$studyField)
            .filter(\.$beginDate <= now)
            .filter(\.$endDate >= now)
            .sort(\.$name, .ascending)
            .all()

        return try classes.map { try SchoolClassDTO(from: $0) }
    }
}
