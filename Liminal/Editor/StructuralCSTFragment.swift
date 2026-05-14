import CambiumBuilder
import CambiumCore
import CambiumSelection
import CambiumSerialization
import Foundation

public struct StructuralCSTFragment: Sendable {
    public let snapshot: GreenTreeSnapshot<LiminalLanguage>

    public init(snapshot: GreenTreeSnapshot<LiminalLanguage>) {
        self.snapshot = snapshot
    }

    public var wrapperKind: LiminalKind {
        snapshot.root.kind
    }

    public var sourceText: String {
        snapshot.root.makeString(using: snapshot.resolver)
    }

    public var childKinds: [LiminalKind] {
        (0..<snapshot.root.childCount).map { snapshot.root.child(at: $0).kind }
    }

    public var hasTokenChildren: Bool {
        for index in 0..<snapshot.root.childCount {
            if case .token = snapshot.root.child(at: index) {
                return true
            }
        }
        return false
    }

    public func serializedData() throws -> Data {
        Data(try snapshot.serializeGreenSnapshot())
    }

    public static func decode(data: Data) throws -> StructuralCSTFragment {
        let snapshot = try GreenSnapshotDecoder.decodeSnapshot(
            Array(data),
            as: LiminalLanguage.self
        )
        return StructuralCSTFragment(snapshot: snapshot)
    }

    public static func capture(_ forest: LiminalForest) throws -> StructuralCSTFragment {
        try forest.parent.withCursor { cursor in
            let wrapperKind = cursor.kind
            let children = cursor.green { parentGreen in
                (forest.firstChildIndex...forest.lastChildIndex).map {
                    parentGreen.child(at: $0)
                }
            }
            let wrapper = try GreenNode<LiminalLanguage>(
                kind: wrapperKind,
                children: children
            )
            return StructuralCSTFragment(
                snapshot: GreenTreeSnapshot(
                    root: wrapper,
                    resolver: cursor.resolver
                )
            )
        }
    }
}
