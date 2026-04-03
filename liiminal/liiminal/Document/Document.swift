import Foundation

struct Document: Equatable, Sendable {
    var blocks: [BlockNode]

    var sourceLength: Int {
        blocks.reduce(0) { $0 + $1.sourceLength }
    }

    var contentLength: Int {
        blocks.reduce(0) { $0 + $1.contentLength }
    }

    /// Find which block contains the given source offset.
    /// Returns (blockIndex, offsetWithinBlock).
    func resolveBlockIndex(at sourceOffset: Int) -> (blockIndex: Int, localOffset: Int)? {
        var remaining = sourceOffset
        for (i, block) in blocks.enumerated() {
            if remaining < block.sourceLength {
                return (i, remaining)
            }
            remaining -= block.sourceLength
        }
        if remaining == 0, !blocks.isEmpty {
            let last = blocks.count - 1
            return (last, blocks[last].sourceLength)
        }
        return nil
    }

    /// Source offset where the block at `index` starts.
    func sourceOffset(ofBlockAt index: Int) -> Int {
        blocks.prefix(index).reduce(0) { $0 + $1.sourceLength }
    }
}
