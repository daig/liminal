import Foundation
import Testing
@testable import Liminal

@Suite("NavigationRouter")
@MainActor
struct NavigationRouterTests {
    @Test("subscriber registered before navigation receives request synchronously")
    func subscribeFirst() {
        let router = NavigationRouter.shared
        router.resetForTesting()
        defer { router.resetForTesting() }
        router.openDocument = { _ in /* no-op */ }

        let url = URL(fileURLWithPath: "/tmp/v/Note.lim")
        let subscriber = StubSubscriber()
        router.subscribe(subscriber, for: url)

        router.navigate(to: url, anchor: .heading("Goals"))

        #expect(subscriber.received.count == 1)
        #expect(subscriber.received.first?.targetURL == VaultRegistry.canonicalNoteURL(for: url))
        #expect(subscriber.received.first?.anchor == .heading("Goals"))
    }

    @Test("navigation arriving before subscriber is queued and drained on subscribe")
    func queueDrainsOnSubscribe() {
        let router = NavigationRouter.shared
        router.resetForTesting()
        defer { router.resetForTesting() }
        var openCalls: [URL] = []
        router.openDocument = { url in openCalls.append(url) }

        let url = URL(fileURLWithPath: "/tmp/v/Note.lim")
        router.navigate(to: url, anchor: .block("para-1"))

        // Queued and openDocument was asked to bring the file up.
        #expect(openCalls.count == 1)
        #expect(router.pendingRequest(for: url) != nil)

        let subscriber = StubSubscriber()
        router.subscribe(subscriber, for: url)

        // Subscribe drained the pending request synchronously.
        #expect(subscriber.received.count == 1)
        #expect(subscriber.received.first?.anchor == .block("para-1"))
        #expect(router.pendingRequest(for: url) == nil)
    }

    @Test("unsubscribe stops further deliveries; navigation re-queues")
    func unsubscribeStopsDelivery() {
        let router = NavigationRouter.shared
        router.resetForTesting()
        defer { router.resetForTesting() }
        var openCalls: [URL] = []
        router.openDocument = { url in openCalls.append(url) }

        let url = URL(fileURLWithPath: "/tmp/v/Note.lim")
        let subscriber = StubSubscriber()
        router.subscribe(subscriber, for: url)
        router.unsubscribe(subscriber, for: url)

        router.navigate(to: url, anchor: nil)

        #expect(subscriber.received.isEmpty)
        #expect(router.pendingRequest(for: url) != nil)
        #expect(openCalls == [VaultRegistry.canonicalNoteURL(for: url)])
    }

    @Test("only the latest queued navigation for a URL survives")
    func queueCoalesces() {
        let router = NavigationRouter.shared
        router.resetForTesting()
        defer { router.resetForTesting() }
        router.openDocument = { _ in /* no-op */ }

        let url = URL(fileURLWithPath: "/tmp/v/Note.lim")
        router.navigate(to: url, anchor: .heading("First"))
        router.navigate(to: url, anchor: .heading("Second"))

        #expect(router.pendingRequest(for: url)?.anchor == .heading("Second"))

        let subscriber = StubSubscriber()
        router.subscribe(subscriber, for: url)
        #expect(subscriber.received.count == 1)
        #expect(subscriber.received.first?.anchor == .heading("Second"))
    }

    @Test("re-subscribing for a URL replaces the prior subscriber")
    func resubscribeReplaces() {
        let router = NavigationRouter.shared
        router.resetForTesting()
        defer { router.resetForTesting() }
        router.openDocument = { _ in }

        let url = URL(fileURLWithPath: "/tmp/v/Note.lim")
        let firstSub = StubSubscriber()
        let secondSub = StubSubscriber()

        router.subscribe(firstSub, for: url)
        router.subscribe(secondSub, for: url)
        router.navigate(to: url, anchor: nil)

        #expect(firstSub.received.isEmpty)
        #expect(secondSub.received.count == 1)
    }

    @Test("URL canonicalization matches across symlink-equivalent paths")
    func canonicalMatching() {
        let router = NavigationRouter.shared
        router.resetForTesting()
        defer { router.resetForTesting() }
        router.openDocument = { _ in }

        // Subscribe with a trailing-slash–normalized path; navigate with
        // a path that the canonicalizer produces the same key for. The
        // expectation is that both reduce to the same dictionary key.
        let subscribed = URL(fileURLWithPath: "/tmp/v/Note.lim")
        let navigatedTo = URL(fileURLWithPath: "/tmp/v/./Note.lim")

        let subscriber = StubSubscriber()
        router.subscribe(subscriber, for: subscribed)
        router.navigate(to: navigatedTo, anchor: nil)

        #expect(subscriber.received.count == 1)
    }
}

@MainActor
private final class StubSubscriber: NavigationSubscriber {
    var received: [NavigationRequest] = []
    nonisolated init() {}

    nonisolated func handleNavigation(_ request: NavigationRequest) {
        MainActor.assumeIsolated {
            received.append(request)
        }
    }
}
