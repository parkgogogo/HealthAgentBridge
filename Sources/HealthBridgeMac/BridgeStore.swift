import Foundation

actor BridgeStore {
    private let fileURL: URL
    private var latest: StoredHealthReport?

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealthAgentBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        self.fileURL = baseURL.appendingPathComponent("latest-report.json")
        self.latest = try? Self.load(from: fileURL)
    }

    func ingest(_ report: HealthReportEnvelope, remoteAddress: String?) throws {
        let stored = StoredHealthReport(receivedAt: Date(), remoteAddress: remoteAddress, report: report)
        let data = try JSONCoding.encoder.encode(stored)
        try data.write(to: fileURL, options: [.atomic])
        latest = stored
    }

    func latestReport() -> StoredHealthReport? {
        latest
    }

    func dailySummaries() -> [DailyHealthSummary] {
        latest?.report.dailySummaries ?? []
    }

    private static func load(from url: URL) throws -> StoredHealthReport {
        let data = try Data(contentsOf: url)
        return try JSONCoding.decoder.decode(StoredHealthReport.self, from: data)
    }
}
