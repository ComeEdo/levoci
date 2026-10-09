import Fluent
import Vapor

/// Modello Fluent per la tabella `timetable_professors` (relazione N a N tra Timetable e User/professori)
final class TimetableProfessor: Model, @unchecked Sendable {
    static let schema = "timetable_professors"

    final class IDValue: Fields, Hashable, @unchecked Sendable {
        @Field(key: "lessonId")
        var lessonId: UUID

        @Field(key: "professorId")
        var professorId: UUID

        init() {}

        init(lessonId: UUID, professorId: UUID) {
            self.lessonId = lessonId
            self.professorId = professorId
        }

        static func == (lhs: IDValue, rhs: IDValue) -> Bool {
            lhs.lessonId == rhs.lessonId && lhs.professorId == rhs.professorId
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(lessonId)
            hasher.combine(professorId)
        }
    }

    @CompositeID
    var id: IDValue?

    init() {}

    init(lessonId: UUID, professorId: UUID) {
        self.id = IDValue(lessonId: lessonId, professorId: professorId)
    }
}
