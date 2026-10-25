import Vapor
import Fluent

// MARK: - Classe Scolastica
struct SchoolClassDTO: Content {
    let id: UUID
    let name: String
    let studyField: StudyFieldDTO?
    let beginDate: String?
    let endDate: String?
    let classYear: Int?

    init(
        id: UUID,
        name: String,
        studyField: StudyFieldDTO? = nil,
        beginDate: String? = nil,
        endDate: String? = nil,
        classYear: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.studyField = studyField
        self.beginDate = beginDate
        self.endDate = endDate
        self.classYear = classYear
    }

    init(from model: SchoolClass) throws {
        let iso = ISO8601DateFormatter()
        self.init(
            id: try model.requireID(),
            name: model.name,
            studyField: try StudyFieldDTO(from: model.studyField),
            beginDate: iso.string(from: model.beginDate),
            endDate: iso.string(from: model.endDate),
            classYear: model.classYear
        )
    }
}

// MARK: - Indirizzo di Studio
struct StudyFieldDTO: Content {
    let id: UUID
    let name: String

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(from model: StudyField) throws {
        self.init(id: try model.requireID(), name: model.name)
    }
}
