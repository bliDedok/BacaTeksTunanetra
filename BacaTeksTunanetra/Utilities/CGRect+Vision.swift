import CoreGraphics

extension CGRect {

    func intersectionOverSmallerArea(with other: CGRect) -> CGFloat {
        let intersectionRect = self.intersection(other)

        guard !intersectionRect.isNull,
              intersectionRect.width > 0,
              intersectionRect.height > 0 else {
            return 0
        }

        let intersectionArea = intersectionRect.width * intersectionRect.height
        let smallerArea = min(self.width * self.height, other.width * other.height)

        guard smallerArea > 0 else {
            return 0
        }

        return intersectionArea / smallerArea
    }

    func centerPoint() -> CGPoint {
        CGPoint(x: midX, y: midY)
    }

    func containsCenter(of other: CGRect) -> Bool {
        contains(other.centerPoint())
    }

    func expandedForHeldObject(_ margin: CGFloat) -> CGRect {
        CGRect(
            x: origin.x - margin,
            y: origin.y - margin,
            width: width + margin * 2,
            height: height + margin * 2
        ).clampedToUnitRect()
    }

    func clampedToUnitRect() -> CGRect {
        let minXValue = max(0, min(minX, 1))
        let minYValue = max(0, min(minY, 1))
        let maxXValue = max(0, min(maxX, 1))
        let maxYValue = max(0, min(maxY, 1))

        return CGRect(
            x: minXValue,
            y: minYValue,
            width: max(0, maxXValue - minXValue),
            height: max(0, maxYValue - minYValue)
        )
    }
}
