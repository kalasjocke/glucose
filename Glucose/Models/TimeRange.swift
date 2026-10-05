import Foundation

enum TimeRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case h1, h3, h6, h12, h24

    var id: String { rawValue }

    var minutes: Int {
        switch self {
        case .h1: return 60
        case .h3: return 180
        case .h6: return 360
        case .h12: return 720
        case .h24: return 1440
        }
    }

    var label: String {
        switch self {
        case .h1: return "1H"
        case .h3: return "3H"
        case .h6: return "6H"
        case .h12: return "12H"
        case .h24: return "24H"
        }
    }

    var xAxisStrideHours: Int {
        switch self {
        case .h1: return 1
        case .h3: return 1
        case .h6: return 1
        case .h12: return 2
        case .h24: return 4
        }
    }
}
