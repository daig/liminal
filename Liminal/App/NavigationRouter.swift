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

    /// Live subscribers, keyed by canonical document URL. **Held
    /// weakly** so that a closed document's Coordinator can be
    /// deallocated normally without us needing to clean up from its
    /// `deinit`. (Strong refs here would synchronously reenter the
    /// `subscribers` dict during `subscribe`'s replace-and-release —
    /// the released old Coordinator's `deinit` would call
    /// `unsubscribe`, which reads the same dict that's mid-mutation.
    /// Swift's exclusivity checker traps that with "Simultaneous
    /// accesses to … modification requires exclusive access".)
    ///
    /// At most one live subscriber per URL: opening an already-open
    /// file just brings its existing window forward (NSDocumentController
    /// dedupes), so resubscribes simply replace the slot.
    private var subscribers: [URL: WeakSubscriber] = [:]

    private struct WeakSubscriber {
        weak var ref: (any NavigationSubscriber)?
    }

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
    /// subscribe). Stale weak entries (subscriber deallocated) are
    /// cleaned up lazily here.
    public func navigate(to targetURL: URL, anchor: LinkNavigationAnchor?) {
        let canonical = VaultRegistry.canonicalNoteURL(for: targetURL)
        let request = NavigationRequest(targetURL: canonical, anchor: anchor)
        if let weak = subscribers[canonical] {
            if let subscriber = weak.ref {
                subscriber.handleNavigation(request)
                return
            }
            // Stale entry — the subscriber was deallocated.
            subscribers.removeValue(forKey: canonical)
        }
        pending[canonical] = request
        openDocument(canonical)
    }

    /// Register a subscriber for `url`. If a request is already
    /// queued for that URL, deliver it immediately and clear the
    /// pending entry.
    public func subscribe(_ subscriber: any NavigationSubscriber, for url: URL) {
        let canonical = VaultRegistry.canonicalNoteURL(for: url)
        subscribers[canonical] = WeakSubscriber(ref: subscriber)
        if let request = pending.removeValue(forKey: canonical) {
            subscriber.handleNavigation(request)
        }
    }

    /// Remove a subscriber. Called when a document changes URL (Save
    /// As). Closed-document cleanup is automatic via the weak ref;
    /// callers don't need to invoke this from `deinit`.
    public func unsubscribe(_ subscriber: any NavigationSubscriber, for url: URL) {
        let canonical = VaultRegistry.canonicalNoteURL(for: url)
        if let weak = subscribers[canonical], weak.ref === subscriber {
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
