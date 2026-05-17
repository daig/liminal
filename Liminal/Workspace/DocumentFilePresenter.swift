import AppKit
import Foundation

/// NSObject helper that conforms to `NSFilePresenter` on behalf of a
/// `LiminalSourceDocument`. The document owns one of these and hands
/// it to `NSFileCoordinator.addFilePresenter(_:)` whenever it has a
/// backing URL. Callbacks from the coordinator hop to MainActor and
/// dispatch back into the document.
///
/// Lives in its own class (rather than making `LiminalSourceDocument`
/// inherit from `NSObject`) because:
/// - `LiminalSourceDocument: ReferenceFileDocument` is constructed off
///   the MainActor by `DocumentGroup` via a `@Sendable` closure;
///   mixing NSObject lifecycle (KVO, retain semantics) into a class
///   with `@Published` properties is fiddly.
/// - `NSFilePresenter`'s required properties (`presentedItemURL`,
///   `presentedItemOperationQueue`) are `@objc` and would collide
///   with the document's existing `@Published var fileURL: URL?`.
///
/// Keeping the presenter separate lets the document just call
/// `presenter.updatePresentedURL(_:)` from its `setFileURL(_:)`
/// chokepoint.
@objc final class DocumentFilePresenter: NSObject, NSFilePresenter {

    /// The presenter's own backing for `presentedItemURL`. Read by
    /// AppKit on its operation queue, written by the document on
    /// MainActor — guarded by `urlAccessQueue` (a barrier dispatch
    /// queue) to keep the cross-thread access safe.
    private var _presentedItemURL: URL?
    private let urlAccessQueue = DispatchQueue(
        label: "sub.dev.liminal.filepresenter.url",
        attributes: .concurrent
    )

    var presentedItemURL: URL? {
        urlAccessQueue.sync { _presentedItemURL }
    }

    /// Strong ref to the underlying dispatch queue. `OperationQueue`
    /// holds `underlyingQueue` as `unowned(unsafe)`, so without this
    /// property the inline DispatchQueue would be deallocated
    /// immediately and the OperationQueue would dangle.
    private let underlyingPresenterQueue = DispatchQueue(
        label: "sub.dev.liminal.filepresenter",
        qos: .userInitiated
    )

    /// Dedicated serial queue, NOT `.main`. Using `.main` here risks
    /// deadlocks when the coordinator is also coordinating a write
    /// the main actor initiated.
    lazy var presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.underlyingQueue = underlyingPresenterQueue
        return queue
    }()

    /// Weak ref back to the document. Callbacks hop to MainActor and
    /// invoke `owner` methods. Releasing the document while the
    /// presenter is still attached is safe — Apple holds presenters
    /// weakly internally, and the weak ref here means any in-flight
    /// callback bails when the owner is gone.
    weak var owner: LiminalSourceDocument?

    init(owner: LiminalSourceDocument?) {
        self.owner = owner
        super.init()
    }

    /// Update the presented URL. Called from `LiminalSourceDocument`'s
    /// `setFileURL(_:)`. Must be called *after* `removeFilePresenter`
    /// and *before* `addFilePresenter` when the URL transitions
    /// between two non-nil values (Save As, navigation in tab).
    func updatePresentedURL(_ url: URL?) {
        urlAccessQueue.async(flags: .barrier) { [weak self] in
            self?._presentedItemURL = url
        }
    }

    // MARK: - NSFilePresenter callbacks

    /// The file's contents changed on disk via someone else — daemon,
    /// another app, another device's iCloud push. Hop to MainActor;
    /// the document decides whether to suppress (self-write) or
    /// prompt the user.
    func presentedItemDidChange() {
        Task { @MainActor [weak owner] in
            owner?.handleExternalChange()
        }
    }

    /// The file was renamed/moved by a coordinated operation. We
    /// update only the presenter's stored URL; the document's
    /// `fileURL` is the authoritative source-of-truth and gets
    /// updated by SwiftUI's separate path. If the two race, the
    /// document's `setFileURL` re-registration dance will reconcile.
    func presentedItemDidMove(to newURL: URL) {
        urlAccessQueue.async(flags: .barrier) { [weak self] in
            self?._presentedItemURL = newURL
        }
    }

    /// The file was deleted via a coordinated operation. v1 behavior:
    /// log + accept. The document keeps its in-memory buffer; the
    /// user's next `:Write` recreates the file at the same path.
    /// Follow-up: prompt "this file was deleted — keep buffer or
    /// close?".
    func accommodatePresentedItemDeletion(
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        // Schedule the owner notification asynchronously, but signal
        // the coordinator immediately so it doesn't block on us. v1
        // contract: we accept the deletion, keep our in-memory buffer
        // (next :Write recreates the file). Returning the completion
        // synchronously also sidesteps capturing the non-Sendable
        // completion closure into the MainActor task.
        completionHandler(nil)
        Task { @MainActor [weak owner] in
            owner?.handlePresentedItemDeletion()
        }
    }
}
