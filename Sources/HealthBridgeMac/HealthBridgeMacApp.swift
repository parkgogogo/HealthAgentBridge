import SwiftUI

@main
struct HealthBridgeMacApp: App {
    @StateObject private var controller = BridgeController()

    var body: some Scene {
        MenuBarExtra("Health Bridge", systemImage: "heart.text.square") {
            MacContentView()
                .environmentObject(controller)
        }
        .menuBarExtraStyle(.window)
    }
}
