import UIKit

final class HealthReporterAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task {
            await HealthReporterService.shared.resumeIfNeeded()
        }
        return true
    }
}
