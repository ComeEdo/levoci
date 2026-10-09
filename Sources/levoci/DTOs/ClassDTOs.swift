import Vapor

// MARK: - Classe Scolastica
struct SchoolClassDTO: Content {
    let id: UUID
    let name: String
    let studyField: StudyFieldDTO?
    let beginDate: String?
    let endDate: String?
    let classYear: Int?
}

// MARK: - Indirizzo di Studio
struct StudyFieldDTO: Content {
    let id: Int
    let name: String
}

// MARK: - Risposta Elenco Classi
struct ClassListResponseDTO: Content {
    let success: Bool
    let message: String
    let data: ClassListData
    
    struct ClassListData: Content {
        let classes: [SchoolClassDTO]
    }
}
