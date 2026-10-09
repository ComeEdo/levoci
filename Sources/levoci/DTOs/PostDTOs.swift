import Vapor

// MARK: - Creazione Post
struct CreatePostRequestDTO: Content {
    let title: String
    let content: String
    let mark: Double
    let valueType: String
    let anonymus: Bool
    let teacherId: UUID?
    let subjectId: Int?
    let isLab: Bool?
    let timetableEntryId: UUID?
    let timetableDate: String?
}

// MARK: - Voto
struct VoteDTO: Content {
    let id: Int?
    let value: Double
    let valueType: String
}

// MARK: - Post Singolo
struct PostResponseDTO: Content {
    let id: UUID
    let title: String
    let content: String
    let anonymus: Bool
    let updatedAt: String?
    let dateOfCreation: String?
    let author: UserProfileDTO?
    let vote: VoteDTO?
    let timetableEntry: LessonDTO?
    let timetableDate: String?
    let subjectEntry: LessonSubjectDTO?
    let professor: UserProfileDTO?
}

// MARK: - Feed dei Post con Delta Sync
struct FeedSyncResponseDTO: Content {
    let success: Bool
    let message: String
    let data: FeedData
    
    struct FeedData: Content {
        let posts: [PostResponseDTO]
        let deletedPostIds: [UUID]
    }
}
