import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = HealthReporterViewModel()
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("健康上报", isOn: Binding(
                    get: { viewModel.isReportingEnabled },
                    set: { viewModel.setReportingEnabled($0) }
                ))
            }

            Section {
                LabeledContent("状态", value: viewModel.statusText)
                LabeledContent("最近成功上报", value: viewModel.lastSyncText)
                LabeledContent("上报目标") {
                    Text(viewModel.targetText)
                        .font(.footnote)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                LabeledContent("待补发", value: viewModel.queuedText)
                if let errorText = viewModel.errorText {
                    LabeledContent("最近错误") {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
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
