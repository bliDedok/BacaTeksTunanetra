import Foundation
import Vision
import CoreMedia
import CoreVideo
import ImageIO
import CoreML

final class HeldObjectRecognitionService {

    private let queue = DispatchQueue(
        label: "HeldObjectRecognitionService.Queue",
        qos: .userInitiated
    )

    private let handDetectionService = HandDetectionService()

    private let minimumObjectConfidence: Float = 0.55
    private let minimumOverlapRatio: CGFloat = 0.12
    private let handExpansionMargin: CGFloat = 0.22
    
    private var isProcessing = false

    private lazy var visionModel: VNCoreMLModel? = {
        do {
            let configuration = MLModelConfiguration()
            let model = try HeldObjectDetector(configuration: configuration).model
            return try VNCoreMLModel(for: model)
        } catch {
            print("Gagal memuat HeldObjectDetector: \(error.localizedDescription)")
            return nil
        }
    }()

    func recognizeHeldObject(
        from sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation,
        completion: @escaping (Result<DetectedHeldObject?, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            if self.isProcessing {
                return
            }

            self.isProcessing = true
            defer {
                self.isProcessing = false
            }

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

                guard let visionModel = self.visionModel else {
                    DispatchQueue.main.async {
                        completion(.success(nil))
                    }
                    return
                }

                let expandedHandRegion = handRegion.expandedForHeldObject(handExpansionMargin)

                let request = VNCoreMLRequest(model: visionModel) { request, error in
                    if let error = error {
                        let message = error.localizedDescription.lowercased()

                        if message.contains("cancel") || message.contains("cancelled") {
                            print("Vision request dibatalkan, diabaikan.")
                            DispatchQueue.main.async {
                                completion(.success(nil))
                            }
                            return
                        }

                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                        return
                    }

                    let observations = request.results as? [VNRecognizedObjectObservation] ?? []

                    if observations.isEmpty {
                        let resultTypes: [String] = request.results?.map { result in
                            String(describing: type(of: result))
                        } ?? []

                        print("Tidak ada object observation. Result types:", resultTypes)

                        DispatchQueue.main.async {
                            completion(.success(nil))
                        }
                        return
                    }

                    let candidates = observations.compactMap { observation -> DetectedObjectCandidate? in
                        guard let bestLabel = observation.labels.first else {
                            return nil
                        }

                        guard bestLabel.confidence >= self.minimumObjectConfidence else {
                            return nil
                        }

                        let rawLabel = bestLabel.identifier

                        guard self.isAllowedHeldObject(rawLabel: rawLabel) else {
                            return nil
                        }

                        let localizedLabel = self.localizeLabel(rawLabel)

                        guard !self.shouldIgnore(label: localizedLabel) else {
                            return nil
                        }

                        return DetectedObjectCandidate(
                            label: localizedLabel,
                            confidence: bestLabel.confidence,
                            boundingBox: observation.boundingBox
                        )
                    }

                    print("YOLO RAW CANDIDATES:", observations.compactMap { observation in
                        observation.labels.first.map {
                            "\($0.identifier) \(Int($0.confidence * 100))%"
                        }
                    })

                    print("YOLO FILTERED CANDIDATES:", candidates.map {
                        "\($0.label) \(Int($0.confidence * 100))%"
                    })
                    
                    let heldCandidates = candidates.filter { candidate in
                        let overlap = candidate.boundingBox.intersectionOverSmallerArea(
                            with: expandedHandRegion
                        )

                        let centerInsideHand = expandedHandRegion.containsCenter(
                            of: candidate.boundingBox
                        )

                        return overlap >= self.minimumOverlapRatio || centerInsideHand
                    }

                    func heldScore(for candidate: DetectedObjectCandidate) -> CGFloat {
                        let overlap = candidate.boundingBox.intersectionOverSmallerArea(
                            with: expandedHandRegion
                        )

                        let centerBonus: CGFloat = expandedHandRegion.containsCenter(
                            of: candidate.boundingBox
                        ) ? 0.35 : 0.0

                        return CGFloat(candidate.confidence) + (overlap * 1.5) + centerBonus
                    }

                    guard let bestHeldObject = heldCandidates.max(by: {
                        heldScore(for: $0) < heldScore(for: $1)
                    }) else {
                        DispatchQueue.main.async {
                            completion(.success(nil))
                        }
                        return
                    }

                    let result = DetectedHeldObject(
                        rawLabel: bestHeldObject.label,
                        spokenLabel: bestHeldObject.label,
                        confidence: bestHeldObject.confidence,
                        handRegion: handRegion
                    )

                    DispatchQueue.main.async {
                        completion(.success(result))
                    }
                }

                request.imageCropAndScaleOption = .scaleFill

                let handler = VNImageRequestHandler(
                    cvPixelBuffer: pixelBuffer,
                    orientation: orientation,
                    options: [:]
                )

                try handler.perform([request])

            } catch {
                let message = error.localizedDescription.lowercased()

                if message.contains("cancel") || message.contains("cancelled") {
                    print("Vision request dibatalkan dari catch, diabaikan.")
                    DispatchQueue.main.async {
                        completion(.success(nil))
                    }
                    return
                }

                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func normalizedLabel(_ label: String) -> String {
        label
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func shouldIgnore(label: String) -> Bool {
        let lowercased = normalizedLabel(label)

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
    
    private func isAllowedHeldObject(rawLabel: String) -> Bool {
        let lowercased = normalizedLabel(rawLabel)

        let allowedKeywords = [
            "cell phone",
            "mobile phone",
            "phone",
            "bottle",
            "book",
            "cup",
            "wine glass",
            "laptop",
            "keyboard",
            "mouse",
            "remote",
            "scissors",
            "spoon",
            "fork",
            "knife"
        ]

        return allowedKeywords.contains { lowercased.contains($0) }
    }

    private func localizeLabel(_ label: String) -> String {
        let lowercased = normalizedLabel(label)

        if lowercased.contains("cell phone") ||
            lowercased.contains("mobile phone") ||
            lowercased.contains("phone") {
            return "handphone"
        }

        if lowercased.contains("bottle") {
            return "botol"
        }

        if lowercased.contains("book") {
            return "buku"
        }

        if lowercased.contains("cup") ||
            lowercased.contains("glass") ||
            lowercased.contains("mug") {
            return "gelas"
        }

        if lowercased.contains("remote") {
            return "remote"
        }

        if lowercased.contains("keyboard") {
            return "keyboard"
        }

        if lowercased.contains("mouse") {
            return "mouse"
        }

        if lowercased.contains("scissors") {
            return "gunting"
        }

        if lowercased.contains("spoon") {
            return "sendok"
        }

        if lowercased.contains("fork") {
            return "garpu"
        }

        if lowercased.contains("knife") {
            return "pisau"
        }

        if lowercased.contains("laptop") {
            return "laptop"
        }

        if lowercased.contains("tv") {
            return "televisi"
        }

        return label
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
