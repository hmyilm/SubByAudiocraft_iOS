import Foundation

// Konum tüm video oranlarında 1080 birimlik görüntü yüksekliğine göre saklanır.
enum SubtitlePosition {
    static let range: ClosedRange<Double> = 30...950

    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 120 }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    static func visibleMargin(_ value: Double, fontSize: Double, rowCount: Int) -> Double {
        let size = fontSize.isFinite ? max(1, fontSize) : 70
        let topLimit = max(range.lowerBound, 1080 - size * Double(max(1, rowCount)) - 24)
        return min(clamped(value), topLimit)
    }
}
