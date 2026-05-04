import Foundation

struct DetectionLogItem: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let mode: DetectionMode
    let prediction: String
    let confidence: Float?
    let processingTime: TimeInterval?
    let groundTruth: String?
    let isCorrect: Bool?

    enum DetectionMode: String, Codable {
        case textReading = "OCR"
        case heldObject = "HELD_OBJECT"
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        mode: DetectionMode,
        prediction: String,
        confidence: Float? = nil,
        processingTime: TimeInterval? = nil,
        groundTruth: String? = nil,
        isCorrect: Bool? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mode = mode
        self.prediction = prediction
        self.confidence = confidence
        self.processingTime = processingTime
        self.groundTruth = groundTruth
        self.isCorrect = isCorrect
    }
}
