import Foundation

enum StringNormalizer {
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let trimmed = lowered.trimmingCharacters(in: .whitespacesAndNewlines)

        let collapsedWhitespace = trimmed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let strippedPunctuation = collapsedWhitespace
            .replacingOccurrences(of: "[^\\p{L}\\p{N}\\s]", with: "", options: .regularExpression)

        return strippedPunctuation
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isMeaningful(_ text: String, minimumLength: Int) -> Bool {
        normalize(text).count >= minimumLength
    }
}
