import Fluent
import Vapor

/// Modello Fluent per la tabella `timetable`
final class Timetable: Model, @unchecked Sendable {
    static let schema = "timetable"

    @ID(key: .id)
    var id: UUID?

    @OptionalParent(key: "classId")
    var schoolClass: SchoolClass?

    @Field(key: "weekDay")
    var weekDay: String

    @Field(key: "startDate")
    var startDate: Date

    @Field(key: "endDate")
    var endDate: Date

    @Field(key: "startTime")
    var startTime: String

    @Field(key: "endTime")
    var endTime: String

    init() {}

    init(id: UUID? = nil, classId: UUID? = nil, weekDay: String, startDate: Date, endDate: Date, startTime: String, endTime: String) {
        self.id = id
        self.$schoolClass.id = classId
        self.weekDay = weekDay
        self.startDate = startDate
        self.endDate = endDate
        self.startTime = startTime
        self.endTime = endTime
    }
}
