import Foundation

@MainActor
final class HealthReporterViewModel: ObservableObject {
    @Published private(set) var isReportingEnabled = false
    @Published private(set) var statusText = "未开启"
    @Published private(set) var lastSyncText = "尚未成功上报"
    @Published private(set) var targetText = "MagicDNS：\(HealthBridgeConstants.tailnetHost):\(HealthBridgeConstants.port)"
    @Published private(set) var queuedText = "无"
    @Published private(set) var errorText: String?

    private let service = HealthReporterService.shared

    func load() async {
        isReportingEnabled = service.isReportingEnabled
        updateStatusText()
        await refreshDisplay()
    }

    func setReportingEnabled(_ enabled: Bool) {
        isReportingEnabled = enabled
        statusText = enabled ? "正在授权并启动" : "正在关闭"

        Task {
            do {
                try await service.setReportingEnabled(enabled)
                await MainActor.run {
                    self.isReportingEnabled = self.service.isReportingEnabled
                    self.updateStatusText()
                }
                await self.refreshDisplay()
            } catch {
                await MainActor.run {
                    self.isReportingEnabled = self.service.isReportingEnabled
                    self.statusText = error.localizedDescription
                }
                await self.refreshDisplay()
            }
        }
    }

    func refreshDisplay() async {
        let queuedCount = await service.pendingReportCount()
        await MainActor.run {
            self.lastSyncText = HealthBridgeDisplayTime.latestSyncText(for: self.service.lastSuccessfulSyncDate)
            self.targetText = self.service.lastSuccessfulEndpoint
                ?? "MagicDNS：\(HealthBridgeConstants.tailnetHost):\(HealthBridgeConstants.port)\n备用 IPv4：\(HealthBridgeConstants.tailnetIPv4):\(HealthBridgeConstants.port)"
            self.queuedText = queuedCount == 0 ? "无" : "\(queuedCount) 条待补发"
            self.errorText = self.service.lastUploadError
            self.updateStatusText()
        }
    }

    private func updateStatusText() {
        if isReportingEnabled {
            if service.lastUploadError == nil {
                statusText = "已开启"
            } else {
                statusText = "已开启，等待 Mac 可达"
            }
        } else {
            statusText = "未开启"
        }
    }
}
