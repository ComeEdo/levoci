import Vapor

// MARK: - Orario Scolastico
struct TimetableResponseDTO: Content {
    let success: Bool
    let message: String
    let data: TimetableData
    
    struct TimetableData: Content {
        let timetable: [LessonDTO]
        let schoolClass: SchoolClassDTO?
    }
}

// MARK: - Singola Lezione / Slot Orario
struct LessonDTO: Content {
    let id: UUID
    let weekDay: String
    let startTime: String
    let endTime: String
    let subjects: [LessonSubjectDTO]?
    let teachers: [UserProfileDTO]?
}

// MARK: - Materia della Lezione
struct LessonSubjectDTO: Content {
    let subjectId: Int
    let isLab: Bool
}
