import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = HealthReporterViewModel()
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            ReportingTab(viewModel: viewModel)
                .tabItem {
                    Label("上报", systemImage: "heart.fill")
                }

            StatusTab(viewModel: viewModel)
                .tabItem {
                    Label("状态", systemImage: "checkmark.circle.fill")
                }

            BridgeAPITab()
                .tabItem {
                    Label("接口", systemImage: "terminal.fill")
                }
        }
        .task {
            await viewModel.load()
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await viewModel.refreshDisplay()
            }
        }
    }
}

private struct ReportingTab: View {
    @ObservedObject var viewModel: HealthReporterViewModel

    var body: some View {
        Form {
            Section {
                Toggle("健康上报", isOn: Binding(
                    get: { viewModel.isReportingEnabled },
                    set: { viewModel.setReportingEnabled($0) }
                ))
            }

            Section("同步概览") {
                LabeledContent("最近成功上报", value: viewModel.lastSyncText)
                LabeledContent("待补发", value: viewModel.queuedText)
            }
        }
    }
}

private struct StatusTab: View {
    @ObservedObject var viewModel: HealthReporterViewModel

    var body: some View {
        Form {
            Section("运行状态") {
                LabeledContent("状态", value: viewModel.statusText)
                LabeledContent("最近成功上报", value: viewModel.lastSyncText)
                LabeledContent("待补发", value: viewModel.queuedText)
            }

            Section("上报目标") {
                DetailTextRow(title: "当前目标", text: viewModel.targetText)
            }

            Section("错误") {
                if let errorText = viewModel.errorText {
                    DetailTextRow(title: "最近错误", text: errorText)
                } else {
                    LabeledContent("最近错误", value: "无")
                }
            }
        }
    }
}

private struct BridgeAPITab: View {
    var body: some View {
        Form {
            Section("Mac Agent") {
                DetailTextRow(
                    title: "Mac 本机",
                    text: "http://127.0.0.1:\(HealthBridgeConstants.port)/v1/agent/context"
                )
                DetailTextRow(
                    title: "Tailscale",
                    text: "http://\(HealthBridgeConstants.tailnetHost):\(HealthBridgeConstants.port)/v1/agent/context"
                )
            }

            Section("常用接口") {
                DetailTextRow(
                    title: "每日汇总",
                    text: "http://127.0.0.1:\(HealthBridgeConstants.port)/v1/summary/daily?days=14"
                )
                DetailTextRow(
                    title: "最近样本",
                    text: "http://127.0.0.1:\(HealthBridgeConstants.port)/v1/samples/recent?type=heartRate&limit=50"
                )
                DetailTextRow(
                    title: "体能训练",
                    text: "http://127.0.0.1:\(HealthBridgeConstants.port)/v1/workouts/recent?days=30&limit=100"
                )
            }

            Section("手机上报") {
                DetailTextRow(title: "MagicDNS", text: HealthBridgeConstants.tailnetIngestURL)
                DetailTextRow(title: "备用 IPv4", text: HealthBridgeConstants.tailnetIPv4IngestURL)
            }
        }
    }
}

private struct DetailTextRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Text(text)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
