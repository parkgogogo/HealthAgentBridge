import Foundation

@MainActor
final class BridgeController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "准备启动"
    @Published private(set) var latestReceivedText = "尚未接收"
    @Published private(set) var latestGeneratedText = "尚未接收"
    @Published private(set) var latestDeviceText = "暂无"

    private let store = BridgeStore()
    private var server: HealthBridgeHTTPServer?
    private var refreshTask: Task<Void, Never>?

    init() {
        Task {
            await start()
        }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.refreshLatest()
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func start() async {
        guard server == nil else { return }

        let server = HealthBridgeHTTPServer(store: store) { [weak self] in
            Task {
                await self?.refreshLatest()
            }
        }
        self.server = server

        do {
            try server.start()
            isRunning = true
            statusText = "正在监听 \(HealthBridgeConstants.port)，Tailscale 可访问"
            await refreshLatest()
        } catch {
            isRunning = false
            statusText = error.localizedDescription
        }
    }

    func refreshLatest() async {
        if let latest = await store.latestReport() {
            latestReceivedText = HealthBridgeDisplayTime.latestSyncText(for: latest.receivedAt)
            latestGeneratedText = HealthBridgeDisplayTime.latestSyncText(for: latest.report.generatedAt)
            latestDeviceText = latest.report.deviceName
        } else {
            latestReceivedText = "尚未接收"
            latestGeneratedText = "尚未接收"
            latestDeviceText = "暂无"
        }
    }
}
