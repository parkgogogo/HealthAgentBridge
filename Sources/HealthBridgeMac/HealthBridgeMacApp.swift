import SwiftUI

@main
struct HealthBridgeMacApp: App {
    @StateObject private var controller = BridgeController()

    var body: some Scene {
        MenuBarExtra("Health Bridge", systemImage: "flame.fill") {
            MacContentView()
                .environmentObject(controller)
        }
        .menuBarExtraStyle(.window)
    }
}
