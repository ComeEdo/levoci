import Fluent
import Vapor

/// Modello Fluent per la tabella `subjects` (materie scolastiche, es. Matematica, Italiano)
final class Subject: Model, @unchecked Sendable {
    static let schema = "subjects"

    @ID(custom: "id")
    var id: Int?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "description")
    var description: String?

    init() {}

    init(id: Int? = nil, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}
