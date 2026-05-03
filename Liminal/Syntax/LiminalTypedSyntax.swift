import CambiumASTSupport
import CambiumCore
import CambiumSyntaxMacros

public protocol LiminalSyntaxNode: TypedSyntaxNode, Sendable, Hashable
    where Lang == LiminalLanguage
{
    static var kind: LiminalKind { get }

    var syntax: SyntaxNodeHandle<LiminalLanguage> { get }

    init(unchecked syntax: SyntaxNodeHandle<LiminalLanguage>)
}

public extension LiminalSyntaxNode {
    static var rawKind: RawSyntaxKind {
        LiminalLanguage.rawKind(for: kind)
    }

    init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        guard syntax.rawKind == Self.rawKind else {
            return nil
        }
        self.init(unchecked: syntax)
    }

    var range: TextRange {
        syntax.textRange
    }

    var sourceText: String {
        syntax.withCursor { node in
            node.makeString()
        }
    }
}

public struct LiminalTokenSyntax: Sendable, Hashable {
    public let syntax: SyntaxTokenHandle<LiminalLanguage>

    public init(_ syntax: SyntaxTokenHandle<LiminalLanguage>) {
        self.syntax = syntax
    }

    public var kind: LiminalKind {
        syntax.withCursor { token in
            token.kind
        }
    }

    public var range: TextRange {
        syntax.withCursor { token in
            token.textRange
        }
    }

    public var text: String {
        syntax.withCursor { token in
            token.makeString()
        }
    }

    public func withTextUTF8<R>(
        _ body: (UnsafeBufferPointer<UInt8>) throws -> R
    ) throws -> R {
        try syntax.withCursor { token in
            try token.withTextUTF8(body)
        }
    }
}

public enum DocumentItemSyntax: Sendable, Hashable {
    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        _ = syntax
        return nil
    }

    public var syntax: SyntaxNodeHandle<LiminalLanguage> {
        switch self {}
    }

    public var range: TextRange {
        switch self {}
    }
}

public enum BlockSyntax: Sendable, Hashable {
    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        _ = syntax
        return nil
    }

    public var syntax: SyntaxNodeHandle<LiminalLanguage> {
        switch self {}
    }

    public var range: TextRange {
        switch self {}
    }
}

public enum InlineSyntax: Sendable, Hashable {
    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        _ = syntax
        return nil
    }

    public var syntax: SyntaxNodeHandle<LiminalLanguage> {
        switch self {}
    }

    public var range: TextRange {
        switch self {}
    }
}

public enum ValueSyntax: Sendable, Hashable {
    public init?(_ syntax: SyntaxNodeHandle<LiminalLanguage>) {
        _ = syntax
        return nil
    }

    public var syntax: SyntaxNodeHandle<LiminalLanguage> {
        switch self {}
    }

    public var range: TextRange {
        switch self {}
    }
}

@CambiumSyntaxNode(LiminalKind.self, for: .root)
public struct RootSyntax: LiminalSyntaxNode {
    public var documentItems: [DocumentItemSyntax] {
        childNodes().compactMap(DocumentItemSyntax.init)
    }

    public var tokens: [LiminalTokenSyntax] {
        directTokens()
    }

    public func tokens(kind: LiminalKind) -> [LiminalTokenSyntax] {
        directTokens(kind: kind)
    }

    public var rawPayloadToken: LiminalTokenSyntax? {
        firstToken(kind: .rawPayloadText)
    }
}

internal extension LiminalSyntaxNode {
    func childNodes() -> [SyntaxNodeHandle<LiminalLanguage>] {
        syntax.withCursor { node in
            var result: [SyntaxNodeHandle<LiminalLanguage>] = []
            node.forEachChild { child in
                result.append(child.makeHandle())
            }
            return result
        }
    }

    func directTokens(kind: LiminalKind? = nil) -> [LiminalTokenSyntax] {
        syntax.withCursor { node in
            var result: [LiminalTokenSyntax] = []
            node.forEachChildOrToken { element in
                switch element {
                case .token(let token) where kind == nil || token.kind == kind:
                    result.append(LiminalTokenSyntax(token.makeHandle()))
                default:
                    break
                }
            }
            return result
        }
    }

    func firstToken(kind: LiminalKind) -> LiminalTokenSyntax? {
        directTokens(kind: kind).first
    }
}
