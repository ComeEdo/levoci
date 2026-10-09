import Fluent
import Vapor

func routes(_ app: Application) throws {
    // Health check REST di base
    app.get { req async in
        [
            "status": "ok",
            "message": "Voci di Corridoio API",
            "environment": req.application.environment.name
        ]
    }

    // Registrazione delle Route Collections per ciascun dominio
    try app.register(collection: AuthController())
    try app.register(collection: UserController())
    try app.register(collection: PostController())
    try app.register(collection: TimetableController())
    try app.register(collection: ClassController())
}
