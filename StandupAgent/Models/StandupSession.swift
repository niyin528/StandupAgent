import Foundation
import SwiftData

@Model
final class StandupSession {
    @Attribute(.unique) var dateString: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SessionMessage.session)
    var messages: [SessionMessage] = []

    init(dateString: String, createdAt: Date = Date()) {
        self.dateString = dateString
        self.createdAt = createdAt
    }

    var sortedMessages: [SessionMessage] {
        messages.sorted { $0.orderIndex < $1.orderIndex }
    }

    static func dateKey(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func date(from dateKey: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: dateKey)
    }
}

@Model
final class SessionMessage {
    var role: String
    var content: String
    var orderIndex: Int
    var timestamp: Date
    var session: StandupSession?

    init(role: String, content: String, orderIndex: Int, timestamp: Date = Date(), session: StandupSession? = nil) {
        self.role = role
        self.content = content
        self.orderIndex = orderIndex
        self.timestamp = timestamp
        self.session = session
    }
}
