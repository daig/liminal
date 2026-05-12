import AppKit
import Foundation

/// Cross-window navigation arbiter. Documents subscribe themselves
/// when their `LiminalSourceDocument` learns its file URL; navigations
/// targeted at an open document deliver immediately to that
/// subscriber. When the target isn't open, the request is queued and
/// `NSDocumentController.openDocument` is asked to open it; the
/// freshly-loaded document consumes its pending request on subscribe.
///
/// Single source of truth for "which window owns which file URL," so
/// Cmd-clicks across documents don't accidentally open duplicate
/// windows.
@MainActor
public final class NavigationRouter {
    public static let shared = NavigationRouter()

    /// Pending navigation requests keyed by canonical target URL.
    /// Drained as soon as a subscriber for that URL appears.
    private var pending: [URL: NavigationRequest] = [:]

    /// Live subscribers, keyed by canonical document URL. There is at
    /// most one subscriber per URL: when the user opens an
    /// already-open file, NSDocumentController focuses the existing
    /// window rather than creating a duplicate, so the existing
    /// subscription is what wins.
    private var subscribers: [URL: any NavigationSubscriber] = [:]

    /// Function used to open a not-yet-open target URL. Defaults to
    /// `NSDocumentController.openDocument`. Tests assign a stub so
    /// they don't fire real document opens.
    var openDocument: @MainActor (URL) -> Void = { url in
        NSDocumentController.shared.openDocument(
            withContentsOf: url,
            display: true
        ) { _, _, error in
            if let error {
                NSLog("NavigationRouter: openDocument failed for \(url.path): \(error)")
            }
        }
    }

    private init() {}

    /// Deliver a navigation to `targetURL`. Already-open subscribers
    /// receive the request synchronously; otherwise the request is
    /// queued and `NSDocumentController` is asked to open the file
    /// (the freshly-loaded document consumes the pending request on
    /// subscribe).
    public func navigate(to targetURL: URL, anchor: LinkNavigationAnchor?) {
        let canonical = VaultRegistry.canonicalNoteURL(for: targetURL)
        let request = NavigationRequest(targetURL: canonical, anchor: anchor)
        if let subscriber = subscribers[canonical] {
            subscriber.handleNavigation(request)
            return
        }
        pending[canonical] = request
        openDocument(canonical)
    }

    /// Register a subscriber for `url`. If a request is already
    /// queued for that URL, deliver it immediately and clear the
    /// pending entry.
    public func subscribe(_ subscriber: any NavigationSubscriber, for url: URL) {
        let canonical = VaultRegistry.canonicalNoteURL(for: url)
        subscribers[canonical] = subscriber
        if let request = pending.removeValue(forKey: canonical) {
            subscriber.handleNavigation(request)
        }
    }

    /// Remove a subscriber. Called when a document changes URL (Save
    /// As) or the view tears down. Idempotent and defends against
    /// late-arriving unsubscribes from a prior URL.
    public func unsubscribe(_ subscriber: any NavigationSubscriber, for url: URL) {
        let canonical = VaultRegistry.canonicalNoteURL(for: url)
        if let current = subscribers[canonical], current === subscriber {
            subscribers.removeValue(forKey: canonical)
        }
    }

    /// Visible for tests so each test runs against a clean router.
    func resetForTesting() {
        pending.removeAll()
        subscribers.removeAll()
    }

    /// Visible for tests — peek at queued requests without
    /// triggering NSDocumentController.
    func pendingRequest(for url: URL) -> NavigationRequest? {
        pending[VaultRegistry.canonicalNoteURL(for: url)]
    }
}

public struct NavigationRequest: Equatable, Sendable {
    public let targetURL: URL
    public let anchor: LinkNavigationAnchor?
    public let nonce: UUID

    public init(
        targetURL: URL,
        anchor: LinkNavigationAnchor?,
        nonce: UUID = UUID()
    ) {
        self.targetURL = targetURL
        self.anchor = anchor
        self.nonce = nonce
    }
}

@MainActor
public protocol NavigationSubscriber: AnyObject {
    func handleNavigation(_ request: NavigationRequest)
}
