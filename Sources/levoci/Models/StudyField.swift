import Fluent
import Vapor

/// Modello Fluent per la tabella `studyFields` (Indirizzi di studio es. Informatica, Elettronica)
final class StudyField: Model, @unchecked Sendable {
    static let schema = "studyFields"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "studyField")
    var name: String

    @OptionalField(key: "description")
    var description: String?

    @Children(for: \.$studyField)
    var classes: [SchoolClass]

    init() {}

    init(id: UUID? = nil, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}
