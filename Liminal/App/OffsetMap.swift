import Foundation

/// O(1) lookup from UTF-8 byte offset to UTF-16 code-unit offset.
/// Either covers the full source (built in one linear pass) or just a
/// sub-range (the per-keystroke "scope-local" build), with the same
/// lookup behavior either way.
///
/// Replaces the O(position) `String.UTF8View.index(_:offsetBy:)` +
/// `utf16.distance` walks that previously dominated the highlight pass
/// on large docs (each conversion was O(position-in-doc); applying N
/// spans was O(N²/2)).
struct OffsetMap {
    /// `table[i]` is the UTF-16 offset corresponding to UTF-8 byte
    /// offset `byteBase + i`. Continuation bytes inside a multi-byte
    /// scalar share the scalar's UTF-16 offset. Size is
    /// `coveredByteCount + 1` so that the end of the covered range is
    /// a valid lookup.
    private let table: [Int]
    /// First byte offset (in source coordinates) covered by `table`.
    /// `0` for the full-source build; the scope's start byte for the
    /// scoped build.
    private let byteBase: Int

    /// Full-source map. O(source byte count) build + memory.
    init(source: String) {
        self.init(source: source, byteRange: nil)
    }

    /// Scope-local map covering only `byteRange`, anchored at the
    /// correct absolute UTF-16 offset.
    ///
    /// `byteRange` is in source coordinates. The build walks unicode
    /// scalars from source byte 0 up to `byteRange.lowerBound` to find
    /// that point's absolute UTF-16 offset (counter-only, no
    /// allocation), then fills the table for bytes in `byteRange`
    /// (allocates O(byteRange length) + 1 entries). Useful when the
    /// caller only needs UTF-16 conversion for a small contiguous
    /// region — the per-keystroke highlight scope, for instance.
    ///
    /// `byteRange.lowerBound` must land on a Unicode-scalar boundary;
    /// otherwise the lookup is meaningless. (Liminal scope boundaries
    /// come from line boundaries, which are always scalar boundaries.)
    init(source: String, byteRange: Range<Int>) {
        self.init(source: source, byteRange: Optional<Range<Int>>.some(byteRange))
    }

    private init(source: String, byteRange: Range<Int>?) {
        let totalBytes = source.utf8.count
        let lower: Int
        let upper: Int
        if let range = byteRange {
            lower = max(0, range.lowerBound)
            upper = min(totalBytes, range.upperBound)
        } else {
            lower = 0
            upper = totalBytes
        }

        var table: [Int] = []
        table.reserveCapacity(max(0, upper - lower) + 1)
        var utf16Position = 0
        var byteCursor = 0

        for scalar in source.unicodeScalars {
            let utf8Len = scalar.utf8.count
            let utf16Len = scalar.utf16.count
            let scalarStart = byteCursor
            let scalarEnd = byteCursor + utf8Len

            if scalarEnd <= lower {
                // Entirely before scope — bump counters only.
                utf16Position += utf16Len
                byteCursor = scalarEnd
                continue
            }
            if scalarStart >= upper {
                // Past scope — stop walking; the trailing table.append
                // below records the UTF-16 offset at `upper`.
                break
            }

            // Overlaps scope. Record this scalar's UTF-16 offset for
            // every byte of the scalar that falls inside `[lower, upper)`.
            let fillStart = max(scalarStart, lower)
            let fillEnd = min(scalarEnd, upper)
            for _ in fillStart..<fillEnd {
                table.append(utf16Position)
            }

            utf16Position += utf16Len
            byteCursor = scalarEnd
        }
        // Sentinel entry so a lookup at the exact end of the covered
        // range yields the right UTF-16 offset.
        table.append(utf16Position)

        self.table = table
        self.byteBase = lower
    }

    /// Number of source bytes this map covers. For the full-source
    /// build this equals the source's UTF-8 byte count; for a scoped
    /// build it equals the scope's byte length.
    var coveredByteCount: Int { table.count - 1 }

    /// Convert a UTF-8 byte range `[start, start + length)` to an
    /// `NSRange` in UTF-16 coordinates. Returns nil for ranges that
    /// fall outside the map's covered region.
    func nsRange(forByteStart start: UInt32, length: UInt32) -> NSRange? {
        let startByte = Int(start)
        let endByte = startByte + Int(length)
        guard startByte >= byteBase,
              endByte >= startByte,
              endByte <= byteBase + (table.count - 1)
        else {
            return nil
        }
        let startUTF16 = table[startByte - byteBase]
        let endUTF16 = table[endByte - byteBase]
        return NSRange(location: startUTF16, length: endUTF16 - startUTF16)
    }
}
