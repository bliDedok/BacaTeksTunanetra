import Foundation
import Vision
import CoreMedia
import CoreVideo
import ImageIO

final class HeldObjectRecognitionService {

    private let queue = DispatchQueue(label: "HeldObjectRecognitionService.Queue", qos: .userInitiated)
    private let handDetectionService = HandDetectionService()

    private let minimumObjectConfidence: Float = 0.20

    func recognizeHeldObject(
        from sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation,
        completion: @escaping (Result<DetectedHeldObject?, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                DispatchQueue.main.async {
                    completion(.success(nil))
                }
                return
            }

            do {
                guard let handRegion = try self.handDetectionService.detectHandRegion(
                    from: pixelBuffer,
                    orientation: orientation
                ) else {
                    DispatchQueue.main.async {
                        completion(.success(nil))
                    }
                    return
                }

                let request = VNClassifyImageRequest { request, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                        return
                    }

                    guard let observations = request.results as? [VNClassificationObservation],
                          !observations.isEmpty else {
                        DispatchQueue.main.async {
                            completion(.success(nil))
                        }
                        return
                    }

                    let bestObservation = observations.first { observation in
                        observation.confidence >= self.minimumObjectConfidence &&
                        !self.shouldIgnore(label: observation.identifier)
                    }

                    guard let bestObservation else {
                        DispatchQueue.main.async {
                            completion(.success(nil))
                        }
                        return
                    }

                    let spokenLabel = self.localizeLabel(bestObservation.identifier)

                    let result = DetectedHeldObject(
                        rawLabel: bestObservation.identifier,
                        spokenLabel: spokenLabel,
                        confidence: bestObservation.confidence,
                        handRegion: handRegion
                    )

                    DispatchQueue.main.async {
                        completion(.success(result))
                    }
                }

                request.regionOfInterest = handRegion

                let handler = VNImageRequestHandler(
                    cvPixelBuffer: pixelBuffer,
                    orientation: orientation,
                    options: [:]
                )

                try handler.perform([request])

            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func shouldIgnore(label: String) -> Bool {
        let lowercased = label.lowercased()

        let ignoredKeywords = [
            "hand",
            "finger",
            "palm",
            "person",
            "human",
            "skin",
            "arm",
            "body"
        ]

        return ignoredKeywords.contains { lowercased.contains($0) }
    }

    private func localizeLabel(_ label: String) -> String {
        let lowercased = label.lowercased()

        if lowercased.contains("cellular telephone") ||
            lowercased.contains("mobile phone") ||
            lowercased.contains("cell phone") ||
            lowercased.contains("iphone") ||
            lowercased.contains("phone") {
            return "handphone"
        }

        if lowercased.contains("wallet") {
            return "dompet"
        }

        if lowercased.contains("bottle") {
            return "botol"
        }

        if lowercased.contains("cup") ||
            lowercased.contains("mug") {
            return "gelas"
        }

        if lowercased.contains("book") {
            return "buku"
        }

        if lowercased.contains("key") {
            return "kunci"
        }

        if lowercased.contains("remote") {
            return "remote"
        }

        if lowercased.contains("pen") {
            return "pulpen"
        }

        if lowercased.contains("spoon") {
            return "sendok"
        }

        return label
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
