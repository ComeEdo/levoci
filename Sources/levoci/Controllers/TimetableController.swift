import Vapor

/// Controller per la consultazione dell'orario scolastico (timetable)
struct TimetableController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let timetableRoutes = routes.grouped("user")
        
        timetableRoutes.get("getTimetable", use: getTimetable)
    }

    @Sendable
    func getTimetable(req: Request) async throws -> Response {
        // TODO: Recupero orario scolastico filtrato per classe o docente e periodo didattico
        throw Abort(.notImplemented)
    }
}
