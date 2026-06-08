import Foundation

enum TrendDirection: Int, Codable, Sendable, CaseIterable {
    case none = 0
    case doubleUp = 1
    case singleUp = 2
    case fortyFiveUp = 3
    case flat = 4
    case fortyFiveDown = 5
    case singleDown = 6
    case doubleDown = 7
    case notComputable = 8
    case rateOutOfRange = 9

    init(rawAny: Any?) {
        if let i = rawAny as? Int, let t = TrendDirection(rawValue: i) {
            self = t
            return
        }
        if let s = rawAny as? String {
            switch s {
            case "None": self = .none
            case "DoubleUp": self = .doubleUp
            case "SingleUp": self = .singleUp
            case "FortyFiveUp": self = .fortyFiveUp
            case "Flat": self = .flat
            case "FortyFiveDown": self = .fortyFiveDown
            case "SingleDown": self = .singleDown
            case "DoubleDown": self = .doubleDown
            case "NotComputable": self = .notComputable
            case "RateOutOfRange": self = .rateOutOfRange
            default: self = .notComputable
            }
            return
        }
        self = .notComputable
    }

    var glyph: String {
        switch self {
        case .doubleUp: return "⇈"
        case .singleUp: return "↑"
        case .fortyFiveUp: return "↗"
        case .flat: return "→"
        case .fortyFiveDown: return "↘"
        case .singleDown: return "↓"
        case .doubleDown: return "⇊"
        case .none, .notComputable, .rateOutOfRange: return "·"
        }
    }

    var sfSymbol: String {
        switch self {
        case .doubleUp: return "arrow.up.to.line"
        case .singleUp: return "arrow.up"
        case .fortyFiveUp: return "arrow.up.right"
        case .flat: return "arrow.right"
        case .fortyFiveDown: return "arrow.down.right"
        case .singleDown: return "arrow.down"
        case .doubleDown: return "arrow.down.to.line"
        case .none, .notComputable, .rateOutOfRange: return "circle"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .doubleUp: return "rising fast"
        case .singleUp: return "rising"
        case .fortyFiveUp: return "rising slowly"
        case .flat: return "stable"
        case .fortyFiveDown: return "falling slowly"
        case .singleDown: return "falling"
        case .doubleDown: return "falling fast"
        case .none, .notComputable, .rateOutOfRange: return "unknown trend"
        }
    }
}
