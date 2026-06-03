import SwiftUI
import AppKit

struct MacContentView: View {
    @EnvironmentObject private var controller: BridgeController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Circle()
                    .fill(controller.isRunning ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(controller.isRunning ? "服务运行中" : "服务未启动")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("刷新") {
                    Task {
                        await controller.refreshLatest()
                    }
                }
                .controlSize(.small)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Agent API")
                        .foregroundStyle(.secondary)
                    Text(HealthBridgeConstants.agentBaseURL)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("iPhone 上报")
                        .foregroundStyle(.secondary)
                    Text(HealthBridgeConstants.tailnetIngestURL)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("备用上报")
                        .foregroundStyle(.secondary)
                    Text(HealthBridgeConstants.tailnetIPv4IngestURL)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Token")
                        .foregroundStyle(.secondary)
                    Text(HealthBridgeConstants.sharedToken)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("最近接收")
                        .foregroundStyle(.secondary)
                    Text(controller.latestReceivedText)
                }
                GridRow {
                    Text("报告生成")
                        .foregroundStyle(.secondary)
                    Text(controller.latestGeneratedText)
                }
                GridRow {
                    Text("设备")
                        .foregroundStyle(.secondary)
                    Text(controller.latestDeviceText)
                }
                GridRow {
                    Text("Health Packet")
                        .foregroundStyle(.secondary)
                    Text(controller.packetQueueText)
                }
            }

            Divider()

            HStack {
                Text(controller.statusText)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 460)
    }
}
