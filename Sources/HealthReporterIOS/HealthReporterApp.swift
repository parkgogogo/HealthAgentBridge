import SwiftUI

@main
struct HealthReporterApp: App {
    @UIApplicationDelegateAdaptor(HealthReporterAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
