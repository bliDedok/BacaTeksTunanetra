import Foundation

struct RecognizedTextItem: Identifiable, Hashable {
    let id: UUID
    let text: String
    let normalizedText: String
    let confidence: Float
    let date: Date

    init(
        id: UUID = UUID(),
        text: String,
        normalizedText: String,
        confidence: Float,
        date: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.normalizedText = normalizedText
        self.confidence = confidence
        self.date = date
    }
}
