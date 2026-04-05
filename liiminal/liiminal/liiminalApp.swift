import SwiftUI

@main
struct liiminalApp: App {
    var body: some Scene {
        WindowGroup {
            if AppRuntime.isRunningUnitTests {
                EmptyView()
            } else {
                ContentView()
            }
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Vault...") {
                    NotificationCenter.default.post(name: .openVault, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let openVault = Notification.Name("openVault")
}

enum AppRuntime {
    static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
