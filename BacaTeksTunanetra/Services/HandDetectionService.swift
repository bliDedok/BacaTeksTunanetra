import Foundation
import Vision
import CoreVideo
import CoreGraphics
import ImageIO

final class HandDetectionService {

    func detectHandRegion(
        from pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> CGRect? {

        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )

        try handler.perform([request])

        guard let observation = request.results?.first else {
            return nil
        }

        let recognizedPoints = try observation.recognizedPoints(.all)

        let validPoints = recognizedPoints.values.filter { point in
            point.confidence > 0.25
        }

        guard !validPoints.isEmpty else {
            return nil
        }

        let xs = validPoints.map { $0.location.x }
        let ys = validPoints.map { $0.location.y }

        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max() else {
            return nil
        }

        let handRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )

        return handRect.expandedByPercentage(1.4).clampedToUnitRect()
    }
}

private extension CGRect {

    func expandedByPercentage(_ percentage: CGFloat) -> CGRect {
        let extraWidth = width * percentage
        let extraHeight = height * percentage

        return CGRect(
            x: origin.x - extraWidth / 2,
            y: origin.y - extraHeight / 2,
            width: width + extraWidth,
            height: height + extraHeight
        )
    }

    func clampedToUnitRect() -> CGRect {
        let newX = max(0, min(origin.x, 1))
        let newY = max(0, min(origin.y, 1))
        let newMaxX = max(0, min(maxX, 1))
        let newMaxY = max(0, min(maxY, 1))

        return CGRect(
            x: newX,
            y: newY,
            width: max(0, newMaxX - newX),
            height: max(0, newMaxY - newY)
        )
    }
}
