import Foundation

enum SnapRegionID: String, Codable, CaseIterable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeftQuarter
    case topRightQuarter
    case bottomLeftQuarter
    case bottomRightQuarter
    case center

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leftHalf:          return "Left Half"
        case .rightHalf:         return "Right Half"
        case .topHalf:           return "Top Half"
        case .bottomHalf:        return "Bottom Half"
        case .topLeftQuarter:    return "Top-Left ¼"
        case .topRightQuarter:   return "Top-Right ¼"
        case .bottomLeftQuarter: return "Bottom-Left ¼"
        case .bottomRightQuarter:return "Bottom-Right ¼"
        case .center:            return "Center"
        }
    }

    var snapRegion: SnapRegion {
        switch self {
        case .leftHalf:          return .leftHalf
        case .rightHalf:         return .rightHalf
        case .topHalf:           return .topHalf
        case .bottomHalf:        return .bottomHalf
        case .topLeftQuarter:    return .topLeftQuarter
        case .topRightQuarter:   return .topRightQuarter
        case .bottomLeftQuarter: return .bottomLeftQuarter
        case .bottomRightQuarter:return .bottomRightQuarter
        case .center:            return .center
        }
    }
}

struct LayoutEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var bundleID: String
    var appName: String
    var snapRegionID: SnapRegionID
    var openURL: String? = nil  // file/folder to open with the app
}

struct AppLayout: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var entries: [LayoutEntry]
}
