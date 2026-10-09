import Fluent
import Vapor

/// Modello Fluent per la tabella `votes` (relazione 1 a molti tra Post e Vote)
final class Vote: Model, @unchecked Sendable {
    static let schema = "votes"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "postId")
    var post: Post

    @OptionalParent(key: "userId")
    var user: User?

    @Field(key: "value")
    var value: Int

    @Field(key: "valueType")
    var valueType: String

    @Timestamp(key: "dateOfCreation", on: .create)
    var dateOfCreation: Date?

    init() {}

    init(id: UUID? = nil, postId: UUID, userId: UUID? = nil, value: Int, valueType: String) {
        self.id = id
        self.$post.id = postId
        self.$user.id = userId
        self.value = value
        self.valueType = valueType
    }
}
