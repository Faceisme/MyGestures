import CoreGraphics
import Foundation

struct GestureMatch {
    var command: GestureCommand
    var distance: CGFloat
}

final class GestureRecognizer {
    private let sampleCount = 64
    private let minimumPathLength: CGFloat = 24

    func bestMatch(points: [CGPoint], commands: [GestureCommand], threshold: CGFloat) -> GestureMatch? {
        guard let best = bestCandidate(points: points, commands: commands) else {
            return nil
        }

        guard best.distance <= threshold else {
            return nil
        }

        return best
    }

    func bestCandidate(points: [CGPoint], commands: [GestureCommand]) -> GestureMatch? {
        guard pathLength(points) >= minimumPathLength,
              let candidate = normalize(points) else {
            return nil
        }

        var best: GestureMatch?

        for command in commands where !command.templates.isEmpty {
            for template in command.templates {
                guard let normalizedTemplate = normalize(template.map(\.cgPoint)) else {
                    continue
                }

                let distance = averageDistance(candidate, normalizedTemplate)
                if best == nil || distance < best!.distance {
                    best = GestureMatch(command: command, distance: distance)
                }
            }
        }

        return best
    }

    func normalize(_ points: [CGPoint]) -> [CGPoint]? {
        guard points.count >= 2 else {
            return nil
        }

        let resampled = resample(points, targetCount: sampleCount)
        guard let scaled = scaleToUnitBox(resampled) else {
            return nil
        }

        return translateToOrigin(scaled)
    }

    private func resample(_ points: [CGPoint], targetCount: Int) -> [CGPoint] {
        let totalLength = pathLength(points)
        guard totalLength > 0 else {
            return Array(repeating: points[0], count: targetCount)
        }

        let interval = totalLength / CGFloat(targetCount - 1)
        var distanceSoFar: CGFloat = 0
        var source = points
        var result = [source[0]]
        var index = 1

        while index < source.count {
            let previous = source[index - 1]
            let current = source[index]
            let segmentLength = distance(previous, current)

            if segmentLength == 0 {
                index += 1
                continue
            }

            if distanceSoFar + segmentLength >= interval {
                let ratio = (interval - distanceSoFar) / segmentLength
                let point = CGPoint(
                    x: previous.x + ratio * (current.x - previous.x),
                    y: previous.y + ratio * (current.y - previous.y)
                )
                result.append(point)
                source.insert(point, at: index)
                distanceSoFar = 0
                index += 1
            } else {
                distanceSoFar += segmentLength
                index += 1
            }
        }

        while result.count < targetCount {
            result.append(source.last ?? result.last ?? .zero)
        }

        if result.count > targetCount {
            result = Array(result.prefix(targetCount))
        }

        return result
    }

    private func scaleToUnitBox(_ points: [CGPoint]) -> [CGPoint]? {
        guard let first = points.first else {
            return nil
        }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        let scale = max(maxX - minX, maxY - minY)
        guard scale > 0.0001 else {
            return nil
        }

        return points.map { point in
            CGPoint(
                x: (point.x - minX) / scale,
                y: (point.y - minY) / scale
            )
        }
    }

    private func translateToOrigin(_ points: [CGPoint]) -> [CGPoint] {
        let center = centroid(points)
        return points.map { point in
            CGPoint(x: point.x - center.x, y: point.y - center.y)
        }
    }

    private func centroid(_ points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }

        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private func averageDistance(_ left: [CGPoint], _ right: [CGPoint]) -> CGFloat {
        let count = min(left.count, right.count)
        guard count > 0 else {
            return .greatestFiniteMagnitude
        }

        let total = (0..<count).reduce(CGFloat(0)) { partial, index in
            partial + distance(left[index], right[index])
        }

        return total / CGFloat(count)
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else {
            return 0
        }

        return (1..<points.count).reduce(CGFloat(0)) { partial, index in
            partial + distance(points[index - 1], points[index])
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
