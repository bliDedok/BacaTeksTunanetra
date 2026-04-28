import Foundation

enum VisionMode {
    case textReading
    case heldObject

    var title: String {
        switch self {
        case .textReading:
            return "Mode baca teks"
        case .heldObject:
            return "Mode kenali objek yang dipegang"
        }
    }

    var voiceMessage: String {
        switch self {
        case .textReading:
            return "Mode baca teks aktif"
        case .heldObject:
            return "Mode kenali objek yang dipegang aktif"
        }
    }
}
