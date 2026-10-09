import Fluent
import Vapor

/// Modello Fluent per la tabella `timetable_subjects` (relazione N a N tra Timetable e coppie materia/laboratorio)
final class TimetableSubject: Model, @unchecked Sendable {
    static let schema = "timetable_subjects"

    final class IDValue: Fields, Hashable, @unchecked Sendable {
        @Field(key: "lessonId")
        var lessonId: UUID

        @Field(key: "subjectId")
        var subjectId: Int

        init() {}

        init(lessonId: UUID, subjectId: Int) {
            self.lessonId = lessonId
            self.subjectId = subjectId
        }

        static func == (lhs: IDValue, rhs: IDValue) -> Bool {
            lhs.lessonId == rhs.lessonId && lhs.subjectId == rhs.subjectId
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(lessonId)
            hasher.combine(subjectId)
        }
    }

    @CompositeID
    var id: IDValue?

    @Field(key: "isLab")
    var isLab: Bool

    init() {}

    init(lessonId: UUID, subjectId: Int, isLab: Bool) {
        self.id = IDValue(lessonId: lessonId, subjectId: subjectId)
        self.isLab = isLab
    }
}
