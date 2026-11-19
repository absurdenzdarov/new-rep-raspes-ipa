import Foundation

enum SearchKind: String, Codable, CaseIterable, Hashable {
    case group, teacher, room

    var title: String {
        switch self {
        case .group: return "Группы"
        case .teacher: return "Преподаватели"
        case .room: return "Кабинеты"
        }
    }

    var single: String {
        switch self {
        case .group: return "Группа"
        case .teacher: return "Преподаватель"
        case .room: return "Кабинет"
        }
    }

    var icon: String {
        switch self {
        case .group: return "person.3.fill"
        case .teacher: return "graduationcap.fill"
        case .room: return "door.left.hand.open"
        }
    }
}

struct Entity: Hashable, Codable, Identifiable {
    var kind: SearchKind
    var name: String

    var id: String { kind.rawValue + "|" + name }
}

/// Запись дня: пара + список групп (для группы — соседи по потоку,
/// для преподавателя и кабинета — все группы, которые на этой паре).
struct DayEntry {
    var lesson: Lesson
    var groups: [String]
}

enum GateState: Equatable {
    case hidden
    case loading
    case failed(String)
}

struct SyncProgress: Sendable {
    var fraction: Double
    var message: String
}
