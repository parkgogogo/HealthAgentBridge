import SwiftUI

@main
struct HealthBridgeMacApp: App {
    @StateObject private var controller = BridgeController()

    var body: some Scene {
        MenuBarExtra {
            MacContentView()
                .environmentObject(controller)
        } label: {
            Image(systemName: "flame.fill")
                .font(.system(size: 18, weight: .semibold))
                .accessibilityLabel("Health Bridge")
        }
        .menuBarExtraStyle(.window)
    }
}
