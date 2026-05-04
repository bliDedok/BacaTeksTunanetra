import Foundation
import CoreGraphics

struct DetectedObjectCandidate {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}
