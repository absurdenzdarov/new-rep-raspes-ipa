import SwiftUI

struct CalPeriod: Codable, Identifiable, Hashable {
    var kind: String
    var label: String
    var start: Date
    var end: Date

    var id: String { kind + "|" + String(start.timeIntervalSince1970) }

    var dayCount: Int {
        let d = AppTime.calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return d + 1
    }
}

struct CalendarData: Codable {
    var startYear: Int
    var groups: [String: [CalPeriod]]
    var diagnostics: String

    var groupNames: [String] {
        return groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

struct CalKindStyle {
    let icon: String
    let color: Color
}

enum CalStyle {
    static func style(_ kind: String) -> CalKindStyle {
        switch kind {
        case "к":
            return CalKindStyle(icon: "sun.max.fill", color: Color(hex: 0x2DE0C4))
        case "па":
            return CalKindStyle(icon: "doc.text.fill", color: Color(hex: 0xFFB020))
        case "гиа":
            return CalKindStyle(icon: "graduationcap.fill", color: Color(hex: 0xFF5C7A))
        case "пдп", "пп":
            return CalKindStyle(icon: "briefcase.fill", color: Color(hex: 0x9B6BFF))
        case "уп":
            return CalKindStyle(icon: "wrench.and.screwdriver.fill", color: Color(hex: 0x3D7BFF))
        case "д", "дэ":
            return CalKindStyle(icon: "rosette", color: Color(hex: 0x35D6FF))
        case "эм", "эк", "кэ":
            return CalKindStyle(icon: "checkmark.seal.fill", color: Color(hex: 0x35D6FF))
        case "х":
            return CalKindStyle(icon: "moon.zzz.fill", color: Color(hex: 0x8A94B8))
        default:
            return CalKindStyle(icon: "calendar", color: Color(hex: 0x5B8CFF))
        }
    }

    /// Короткое название вида для легенды
    static func legend(_ kind: String) -> String {
        switch kind {
        case "к": return "Каникулы"
        case "па": return "Сессия"
        case "гиа": return "ГИА"
        case "пдп": return "Преддипломная"
        case "уп": return "Учебная практика"
        case "пп": return "Производств. практика"
        case "д", "дэ": return "Демоэкзамен"
        case "эм": return "Экзамен по модулю"
        case "эк", "кэ": return "Квалиф. экзамен"
        case "х": return "Выходной"
        default: return kind.uppercased()
        }
    }
}
