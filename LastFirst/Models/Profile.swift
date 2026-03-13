import Foundation

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var username: String?
    var displayName: String?
    var readingLevel: String?
    var interests: [String]?
    var preferredSessionMinutes: Int?
    var dailyGoalArticles: Int?
    var userTasteSummary: String?
    var timezone: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case readingLevel = "reading_level"
        case interests
        case preferredSessionMinutes = "preferred_session_minutes"
        case dailyGoalArticles = "daily_goal_articles"
        case userTasteSummary = "user_taste_summary"
        case timezone
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
