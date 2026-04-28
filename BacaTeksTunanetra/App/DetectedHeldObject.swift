import Foundation
import CoreGraphics

struct DetectedHeldObject {
    let rawLabel: String
    let spokenLabel: String
    let confidence: Float
    let handRegion: CGRect
}
