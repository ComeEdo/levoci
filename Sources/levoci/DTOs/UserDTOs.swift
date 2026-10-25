import Vapor
import Fluent

// MARK: - Profilo Utente
struct UserProfileDTO: Content {
    let userId: UUID
    let firstName: String
    let lastName: String
    let username: String
    let roleId: Int?
    let profileImageId: UUID?
    let schoolClass: SchoolClassDTO?

    init(
        userId: UUID,
        firstName: String,
        lastName: String,
        username: String,
        roleId: Int?,
        profileImageId: UUID? = nil,
        schoolClass: SchoolClassDTO? = nil
    ) {
        self.userId = userId
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
        self.roleId = roleId
        self.profileImageId = profileImageId
        self.schoolClass = schoolClass
    }

    init(from user: User) throws {
        self.init(
            userId: try user.requireID(),
            firstName: user.name,
            lastName: user.surname,
            username: user.username,
            roleId: user.$role.id,
            profileImageId: user.profileImageId,
            schoolClass: try user.schoolClass.map { try SchoolClassDTO(from: $0) }
        )
    }
}

// MARK: - Raggruppamento per Ruolo (usato in Login)
struct RoleGroupDTO: Content {
    let roleId: Int
    let users: [UserProfileDTO]
}
