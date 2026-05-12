import CambiumCore
import Foundation

/// Pure dispatch from a click position to a `LinkActivationDecision`,
/// independent of AppKit. Lets every branch be exercised from tests
/// without hosting an `NSTextView`. The Coordinator wires this into
/// the click pipeline; the navigation router consumes the result.
@MainActor
public enum CmdClickHandler {
    /// Look up the innermost reference containing `byteOffset` in
    /// `documentIndex`, resolve it against `vaultLinkIndex`, and
    /// translate to an activation decision. Returns `nil` when the
    /// click point is not inside any reference — the caller falls
    /// back to normal cursor placement.
    public static func decision(
        atByteOffset byteOffset: TextSize,
        documentURL: URL,
        documentIndex: DocumentIndex,
        vaultLinkIndex: VaultLinkIndex
    ) -> Result? {
        guard let reference = documentIndex.reference(containing: byteOffset) else {
            return nil
        }
        let resolution = vaultLinkIndex.resolve(
            target: reference.target,
            from: documentURL
        )
        let decision = LinkActivationPolicy.decision(
            for: reference.target,
            resolution: resolution
        )
        return Result(reference: reference, decision: decision)
    }

    public struct Result: Equatable, Sendable {
        public let reference: DocumentReference
        public let decision: LinkActivationDecision
    }
}
