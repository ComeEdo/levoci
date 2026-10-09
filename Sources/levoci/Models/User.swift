import Fluent
import Vapor

/// Modello Fluent per la tabella `users` (Profilo anagrafico e accademico)
final class User: Model, @unchecked Sendable, Authenticatable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "surname")
    var surname: String

    @Field(key: "username")
    var username: String

    @Parent(key: "roleId")
    private(set) var role: Role

    @Field(key: "userVersion")
    private(set) var userVersion: UUID

    @OptionalParent(key: "classId")
    var schoolClass: SchoolClass?

    @OptionalParent(key: "credentialsId")
    var credentials: Credentials?

    @OptionalField(key: "profileImageId")
    var profileImageId: UUID?

    @Timestamp(key: "dateOfCreation", on: .create)
    var dateOfCreation: Date?

    @Timestamp(key: "lastUpdated", on: .update)
    var lastUpdated: Date?

    @Children(for: \.$author)
    var posts: [Post]

    @Children(for: \.$user)
    var votes: [Vote]

    init() {}

    init(id: UUID? = nil, name: PersonName, surname: PersonName, username: Username, role: UserRole = .student, classId: UUID? = nil, credentialsId: UUID? = nil, profileImageId: UUID? = nil) {
        self.id = id
        self.name = name.value
        self.surname = surname.value
        self.username = username.value
        self.$role.id = role.rawValue
        self.userVersion = UUID()
        self.$schoolClass.id = classId
        self.$credentials.id = credentialsId
        self.profileImageId = profileImageId
    }
}

extension User {
    var roleType: UserRole? {
        UserRole(rawValue: self.$role.id)
    }

    /// Rigenera lo `userVersion` e salva sul database, segnalando che i dati del profilo sono cambiati
    /// e richiedendo il refresh dello `UserToken` da parte dei client.
    func bumpVersion(on db: any Database) async throws {
        self.userVersion = UUID()
        try await self.save(on: db)
    }

    /// Modifica il ruolo dell'utente e incrementa contestualmente lo `userVersion`
    /// per forzare il rinnovo dello UserToken del client.
    func changeRole(to newRole: UserRole, on db: any Database) async throws {
        self.$role.id = newRole.rawValue
        try await self.bumpVersion(on: db)
    }
    
    /// Modifica lo username dell'utente a partire da un `Username` validato e incrementa
    /// contestualmente lo `userVersion` per forzare il rinnovo dello UserToken del client.
    func changeUsername(to newUsername: Username, on db: any Database) async throws {
        self.username = newUsername.value
        try await self.bumpVersion(on: db)
    }
}
