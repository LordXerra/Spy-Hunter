import CoreGraphics

/// Small deterministic PRNG (xorshift64*), so a given seed always lays out the
/// same track. Keeps generation reproducible for testing and tuning.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    /// xorshift64*, whose output multiply gives far better bit mixing than
    /// plain xorshift — the raw variant produced visibly streaky sequences.
    mutating func nextBits() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }

    /// Uniform 0..<1.
    mutating func next() -> CGFloat {
        CGFloat(nextBits() >> 11) / CGFloat(UInt64(1) << 53)
    }

    mutating func cgFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
        range.lowerBound + next() * (range.upperBound - range.lowerBound)
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = range.upperBound - range.lowerBound + 1
        return range.lowerBound + Int(next() * CGFloat(span)) % span
    }
}
