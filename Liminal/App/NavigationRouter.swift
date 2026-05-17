import AppKit
import Foundation

public enum NavigationDisposition: Equatable, Sendable {
    case replaceInCurrentTab
    case newTab
    case newWindow

    static func click(modifierFlags: NSEvent.ModifierFlags = NSEvent.modifierFlags) -> Self {
        modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
            ? .newTab
            : .replaceInCurrentTab
    }
}

/// Cross-window/workspace navigation arbiter. Workspace windows register
/// themselves when they become key, and document views subscribe when their
/// `LiminalSourceDocument` learns its file URL.
///
/// Default navigations target the active workspace so clicking links replaces
/// the active note in-place. Explicit new-tab navigations are also handled by
/// that workspace. Explicit new-window navigations, or navigations made before
/// any workspace is active, fall back to `NSDocumentController.openDocument`.
///
/// Document views still own final anchor application: the workspace chooses
/// which tab/document should be active, then that tab's text view scrolls to
/// the requested anchor once it is mounted.
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
    private weak var activeWorkspace: (any WorkspaceNavigationSubscriber)?

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

    /// Deliver a navigation to `targetURL`. Default and new-tab requests go
    /// through the active workspace when one exists; explicit new-window
    /// requests use the document controller path.
    public func navigate(
        to targetURL: URL,
        anchor: LinkNavigationAnchor?,
        disposition: NavigationDisposition = .replaceInCurrentTab
    ) {
        let canonical = VaultRegistry.canonicalNoteURL(for: targetURL)
        let request = NavigationRequest(targetURL: canonical, anchor: anchor)

        switch disposition {
        case .replaceInCurrentTab, .newTab:
            if let activeWorkspace {
                activeWorkspace.handleNavigation(request, disposition: disposition)
                return
            }
            openInDocumentWindow(request)
        case .newWindow:
            openInDocumentWindow(request)
        }
    }

    /// Workspace controllers call this when their containing window becomes
    /// key, making them the target for subsequent default navigations.
    public func activateWorkspace(_ workspace: any WorkspaceNavigationSubscriber) {
        activeWorkspace = workspace
    }

    /// Clear the active workspace if it is the one currently registered.
    public func deactivateWorkspace(_ workspace: any WorkspaceNavigationSubscriber) {
        if let activeWorkspace,
           activeWorkspace as AnyObject === workspace as AnyObject {
            self.activeWorkspace = nil
        }
    }

    /// Forward `:Quit` to the active workspace's `closeActiveTab`.
    /// Returns the workspace's result: `true` if a tab was closed,
    /// `false` if there's no active workspace OR the workspace is
    /// down to its last tab (caller closes the window instead).
    public func closeActiveWorkspaceTab() -> Bool {
        activeWorkspace?.closeActiveTab() ?? false
    }

    private func openInDocumentWindow(_ request: NavigationRequest) {
        if deliverToOpenDocument(request) {
            return
        }
        pending[request.targetURL] = request
        openDocument(request.targetURL)
    }

    private func deliverToOpenDocument(_ request: NavigationRequest) -> Bool {
        let canonical = VaultRegistry.canonicalNoteURL(for: request.targetURL)
        if let weak = subscribers[canonical] {
            if let subscriber = weak.ref {
                subscriber.handleNavigation(request)
                return true
            }
            // Stale entry — the subscriber was deallocated.
            subscribers.removeValue(forKey: canonical)
        }
        return false
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
        activeWorkspace = nil
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

@MainActor
public protocol WorkspaceNavigationSubscriber: AnyObject {
    func handleNavigation(_ request: NavigationRequest, disposition: NavigationDisposition)
    /// Close the currently-active tab. Returns `true` if a tab was
    /// closed; `false` when this is the only tab in the window (caller
    /// is responsible for closing the window). Drives `:Quit`.
    func closeActiveTab() -> Bool
}

public extension WorkspaceNavigationSubscriber {
    /// Default no-op so existing conformers that haven't implemented
    /// the close path stay source-compatible. Production
    /// `WorkspaceWindowController` overrides.
    func closeActiveTab() -> Bool { false }
}
