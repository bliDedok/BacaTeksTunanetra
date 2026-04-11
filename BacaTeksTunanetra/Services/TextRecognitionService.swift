import Foundation
import Vision
import CoreMedia
import ImageIO

final class TextRecognitionService {
    struct OCRResult {
        let text: String
        let averageConfidence: Float
    }

    private let queue = DispatchQueue(label: "TextRecognitionService.Queue", qos: .userInitiated)

    func recognizeText(
        from sampleBuffer: CMSampleBuffer,
        minimumConfidence: Float,
        orientation: CGImagePropertyOrientation,
        completion: @escaping (Result<OCRResult?, Error>) -> Void
    ) {
        queue.async {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                DispatchQueue.main.async {
                    completion(.success(nil))
                }
                return
            }

            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    DispatchQueue.main.async {
                        completion(.success(nil))
                    }
                    return
                }

                let candidates = observations.compactMap { observation -> (String, Float)? in
                    guard let topCandidate = observation.topCandidates(1).first else { return nil }
                    let confidence = topCandidate.confidence
                    guard confidence >= minimumConfidence else { return nil }
                    return (topCandidate.string, confidence)
                }

                guard !candidates.isEmpty else {
                    DispatchQueue.main.async {
                        completion(.success(nil))
                    }
                    return
                }

                let joinedText = candidates
                    .map(\.0)
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let averageConfidence = candidates.map(\.1).reduce(0, +) / Float(candidates.count)

                let result = OCRResult(text: joinedText, averageConfidence: averageConfidence)
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["id-ID", "en-US"]

            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )

            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
