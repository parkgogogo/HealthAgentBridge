import Charts
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = HealthReporterViewModel()
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            WorkoutTab(viewModel: viewModel)
                .tabItem {
                    Label("运动", systemImage: "chart.bar.fill")
                }

            StatusTab(viewModel: viewModel)
                .tabItem {
                    Label("状态", systemImage: "checkmark.circle.fill")
                }
        }
        .task {
            await viewModel.load()
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await viewModel.refreshDisplay()
                await viewModel.refreshWorkoutChart()
            }
        }
    }
}

private struct WorkoutTab: View {
    @ObservedObject var viewModel: HealthReporterViewModel

    var body: some View {
        Form {
            Section("Workout 卡路里") {
                if viewModel.hasWorkoutCalories {
                    Chart(viewModel.workoutCalories) { point in
                        BarMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value("卡路里", point.kilocalories)
                        )
                        .foregroundStyle(.green)
                    }
                    .frame(height: 220)
                } else {
                    ContentUnavailableView(
                        "暂无图表数据",
                        systemImage: "chart.bar",
                        description: Text(viewModel.workoutChartMessage ?? "最近 30 天没有 workout 卡路里")
                    )
                    .frame(minHeight: 220)
                }
            }

            Section("30 天概览") {
                LabeledContent("总消耗", value: viewModel.workoutCaloriesTotalText)
                LabeledContent("训练次数", value: viewModel.workoutCountText)
                LabeledContent("活跃天数", value: viewModel.workoutActiveDaysText)
                DetailTextRow(title: "最近训练", text: viewModel.latestWorkoutText)
            }
        }
    }
}

private struct StatusTab: View {
    @ObservedObject var viewModel: HealthReporterViewModel

    var body: some View {
        Form {
            Section {
                Toggle("健康上报", isOn: Binding(
                    get: { viewModel.isReportingEnabled },
                    set: { viewModel.setReportingEnabled($0) }
                ))
            }

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
