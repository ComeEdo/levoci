import Fluent
import Vapor

/// Modello Fluent per la tabella `posts`
final class Post: Model, @unchecked Sendable {
    static let schema = "posts"

    @ID(key: .id)
    var id: UUID?

    @OptionalParent(key: "userId")
    var author: User?

    @Field(key: "title")
    var title: String

    @Field(key: "content")
    var content: String

    @Children(for: \.$post)
    var votes: [Vote]

    @Field(key: "isAnonymous")
    var isAnonymous: Bool

    @OptionalField(key: "professorId")
    var professorId: UUID?

    @OptionalField(key: "subjectId")
    var subjectId: Int?

    @OptionalField(key: "isLab")
    var isLab: Bool?

    @OptionalField(key: "timetableId")
    var timetableId: UUID?

    @OptionalField(key: "timetableDate")
    var timetableDate: Date?

    @Timestamp(key: "dateOfCreation", on: .create)
    var dateOfCreation: Date?

    @Timestamp(key: "updatedAt", on: .update)
    var updatedAt: Date?

    @Timestamp(key: "deletedAt", on: .delete)
    var deletedAt: Date?

    init() {}

    init(id: UUID? = nil, authorId: UUID? = nil, title: String, content: String, isAnonymous: Bool, professorId: UUID? = nil, subjectId: Int? = nil, isLab: Bool? = nil, timetableId: UUID? = nil, timetableDate: Date? = nil) {
        self.id = id
        self.$author.id = authorId
        self.title = title
        self.content = content
        self.isAnonymous = isAnonymous
        self.professorId = professorId
        self.subjectId = subjectId
        self.isLab = isLab
        self.timetableId = timetableId
        self.timetableDate = timetableDate
    }
}
