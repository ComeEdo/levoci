import Fluent
import Vapor

/// Modello Fluent per la tabella `roles` (es. 1: Admin, 2: Studente, 3: Docente)
final class Role: Model, @unchecked Sendable {
    static let schema = "roles"

    @ID(custom: "id")
    var id: Int?

    @Field(key: "roleName")
    var roleName: String
    
    @OptionalField(key: "description")
    var description: String?

    @Children(for: \.$role)
    var users: [User]

    init() {}

    init(id: Int? = nil, roleName: String, description: String? = nil) {
        self.id = id
        self.roleName = roleName
        self.description = description
    }
}

/// Ruoli predefiniti nel sistema
enum UserRole: Int, Codable, Sendable, CaseIterable {
    case admin = 1
    case student = 2
    case teacher = 3
    case principal = 4
    case secretariat = 5

    var roleName: String {
        switch self {
        case .admin: return "admin"
        case .student: return "student"
        case .teacher: return "teacher"
        case .principal: return "principal"
        case .secretariat: return "secretariat"
        }
    }
}
