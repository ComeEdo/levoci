import Fluent
import Vapor

/// Modello Fluent per la tabella `real_subjects` (coppia materia/laboratorio, chiave primaria composita)
final class RealSubject: Model, @unchecked Sendable {
    static let schema = "real_subjects"

    final class IDValue: Fields, Hashable, @unchecked Sendable {
        @Field(key: "subjectId")
        var subjectId: Int

        @Field(key: "isLab")
        var isLab: Bool

        init() {}

        init(subjectId: Int, isLab: Bool) {
            self.subjectId = subjectId
            self.isLab = isLab
        }

        static func == (lhs: IDValue, rhs: IDValue) -> Bool {
            lhs.subjectId == rhs.subjectId && lhs.isLab == rhs.isLab
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(subjectId)
            hasher.combine(isLab)
        }
    }

    @CompositeID
    var id: IDValue?

    init() {}

    init(subjectId: Int, isLab: Bool) {
        self.id = IDValue(subjectId: subjectId, isLab: isLab)
    }
}
