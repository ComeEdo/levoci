import Fluent
import Vapor

/// Modello Fluent per la tabella `classes`
final class SchoolClass: Model, @unchecked Sendable {
    static let schema = "classes"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "class")
    var name: String

    @Parent(key: "studyFieldId")
    var studyField: StudyField

    @Field(key: "beginDate")
    var beginDate: Date

    @Field(key: "endDate")
    var endDate: Date

    @Field(key: "classYear")
    var classYear: Int

    @Children(for: \.$schoolClass)
    var students: [User]

    init() {}

    init(id: UUID? = nil, name: String, studyFieldId: UUID, beginDate: Date, endDate: Date, classYear: Int) {
        self.id = id
        self.name = name
        self.$studyField.id = studyFieldId
        self.beginDate = beginDate
        self.endDate = endDate
        self.classYear = classYear
    }
}
