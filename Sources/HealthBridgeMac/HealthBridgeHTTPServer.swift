import Foundation
import Network

final class HealthBridgeHTTPServer {
    private let store: BridgeStore
    private let onIngest: @MainActor () -> Void
    private let queue = DispatchQueue(label: "HealthBridge.HTTPServer")
    private var listener: NWListener?

    init(store: BridgeStore, onIngest: @escaping @MainActor () -> Void = {}) {
        self.store = store
        self.onIngest = onIngest
    }

    func start() throws {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: HealthBridgeConstants.port)!)
        listener.service = NWListener.Service(
            name: HealthBridgeConstants.serviceName,
            type: HealthBridgeConstants.bonjourType
        )

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                NSLog("HealthBridge listener failed: \(error.localizedDescription)")
            }
        }

        listener.start(queue: queue)
        self.listener = listener
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(on: connection, buffer: Data())
    }

    private func readRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                NSLog("HealthBridge read error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let request = HTTPRequest.parse(nextBuffer) {
                Task {
                    let response = await self.route(request, remoteAddress: self.remoteAddress(for: connection.endpoint))
                    self.send(response, on: connection)
                }
            } else if isComplete {
                send(.badRequest(message: "Incomplete HTTP request"), on: connection)
            } else {
                readRequest(on: connection, buffer: nextBuffer)
            }
        }
    }

    private func route(_ request: HTTPRequest, remoteAddress: String?) async -> HTTPResponse {
        if request.method == "OPTIONS" {
            return .noContent()
        }

        let isLocal = remoteAddress.map(isLoopbackAddress) ?? false
        if !isLocal && !request.hasBearerToken(HealthBridgeConstants.sharedToken) {
            return .unauthorized()
        }

        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/v1/status"):
            let latest = await store.latestReport()
            return .json(BridgeStatusPayload.make(from: latest))

        case ("GET", "/v1/summary/daily"):
            let summaries = await store.dailySummaries()
            return .json(filteredDailySummaries(summaries, days: request.optionalBoundedIntQuery("days", min: 1, max: 365)))

        case ("GET", "/v1/report/latest"):
            guard let latest = await store.latestReport() else {
                return .notFound(message: "No health report has been received")
            }
            return .json(latest)

        case ("GET", "/v1/samples/recent"):
            guard let latest = await store.latestReport() else {
                return .notFound(message: "No health report has been received")
            }

            let limit = request.boundedIntQuery("limit", default: 50, min: 1, max: 1_000)
            let type = request.queryItems["type"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let samples = makeRecentSamples(from: latest.report.samples, type: type, limit: limit)
            return .json(samples)

        case ("GET", "/v1/agent/context"):
            guard let latest = await store.latestReport() else {
                return .notFound(message: "No health report has been received")
            }

            let days = request.boundedIntQuery("days", default: 14, min: 1, max: 365)
            let sampleLimit = request.boundedIntQuery("sampleLimit", default: 20, min: 0, max: 500)
            return .json(AgentHealthContext.make(from: latest, days: days, sampleLimit: sampleLimit))

        case ("GET", "/openapi.json"), ("GET", "/v1/openapi.json"):
            return .json(OpenAPIDocument.make())

        case ("POST", "/v1/ingest"):
            do {
                let report = try JSONCoding.decoder.decode(HealthReportEnvelope.self, from: request.body)
                guard report.schemaVersion == HealthBridgeConstants.schemaVersion else {
                    return .badRequest(message: "Unsupported schemaVersion")
                }
                try await store.ingest(report, remoteAddress: remoteAddress)
                await MainActor.run {
                    onIngest()
                }
                return .json(["status": "accepted"])
            } catch {
                return .badRequest(message: error.localizedDescription)
            }

        default:
            return .notFound(message: "Unknown route")
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func remoteAddress(for endpoint: NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint else { return nil }
        return "\(host)"
    }

    private func isLoopbackAddress(_ address: String) -> Bool {
        address == "127.0.0.1" || address == "::1" || address == "localhost"
    }
}

private struct HTTPRequest {
    var method: String
    var target: String
    var path: String
    var queryItems: [String: String]
    var headers: [String: String]
    var body: Data

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let divider = Data("\r\n\r\n".utf8).firstRange(in: data) else {
            return nil
        }

        let headerData = data[..<divider.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }
        let target = parts[1]
        let components = URLComponents(string: target)
        let parsedPath = components?.path.isEmpty == false ? components?.path : nil
        var queryItems: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            if let value = item.value {
                queryItems[item.name] = value
            }
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = divider.upperBound
        guard data.count >= bodyStart + contentLength else {
            return nil
        }

        return HTTPRequest(
            method: parts[0],
            target: target,
            path: parsedPath ?? target,
            queryItems: queryItems,
            headers: headers,
            body: data[bodyStart..<(bodyStart + contentLength)]
        )
    }

    func hasBearerToken(_ token: String) -> Bool {
        headers["authorization"] == "Bearer \(token)"
    }

    func boundedIntQuery(_ name: String, default defaultValue: Int, min: Int, max: Int) -> Int {
        optionalBoundedIntQuery(name, min: min, max: max) ?? defaultValue
    }

    func optionalBoundedIntQuery(_ name: String, min: Int, max: Int) -> Int? {
        guard let rawValue = queryItems[name], let value = Int(rawValue) else {
            return nil
        }
        return Swift.min(Swift.max(value, min), max)
    }
}

private struct HTTPResponse {
    var statusCode: Int
    var statusText: String
    var contentType: String
    var body: Data

    var data: Data {
        let head = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Headers: Authorization, Content-Type\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Connection: close\r
        \r

        """
        var output = Data(head.utf8)
        output.append(body)
        return output
    }

    static func json<T: Encodable>(_ value: T) -> HTTPResponse {
        let body = (try? JSONCoding.encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(statusCode: 200, statusText: "OK", contentType: "application/json", body: body)
    }

    static func noContent() -> HTTPResponse {
        HTTPResponse(statusCode: 204, statusText: "No Content", contentType: "application/json", body: Data())
    }

    static func unauthorized() -> HTTPResponse {
        jsonError(statusCode: 401, statusText: "Unauthorized", message: "Missing or invalid bearer token")
    }

    static func badRequest(message: String) -> HTTPResponse {
        jsonError(statusCode: 400, statusText: "Bad Request", message: message)
    }

    static func notFound(message: String) -> HTTPResponse {
        jsonError(statusCode: 404, statusText: "Not Found", message: message)
    }

    private static func jsonError(statusCode: Int, statusText: String, message: String) -> HTTPResponse {
        let body = (try? JSONCoding.encoder.encode(["error": message])) ?? Data("{}".utf8)
        return HTTPResponse(statusCode: statusCode, statusText: statusText, contentType: "application/json", body: body)
    }
}

private struct BridgeStatusPayload: Encodable {
    var status: String
    var agentBaseURL: String
    var agentContextURL: String
    var dailySummaryURL: String
    var recentSamplesURL: String
    var tailnetIngestURL: String
    var tailnetIPv4IngestURL: String
    var latestReceivedAt: Date?
    var latestGeneratedAt: Date?
    var latestReceivedAgeSeconds: Int?
    var latestGeneratedAgeSeconds: Int?
    var deviceName: String?
    var remoteAddress: String?

    static func make(from latest: StoredHealthReport?) -> BridgeStatusPayload {
        let now = Date()
        return BridgeStatusPayload(
            status: "ok",
            agentBaseURL: HealthBridgeConstants.agentBaseURL,
            agentContextURL: "\(HealthBridgeConstants.agentBaseURL)/v1/agent/context",
            dailySummaryURL: "\(HealthBridgeConstants.agentBaseURL)/v1/summary/daily?days=14",
            recentSamplesURL: "\(HealthBridgeConstants.agentBaseURL)/v1/samples/recent?type=heartRate&limit=50",
            tailnetIngestURL: HealthBridgeConstants.tailnetIngestURL,
            tailnetIPv4IngestURL: HealthBridgeConstants.tailnetIPv4IngestURL,
            latestReceivedAt: latest?.receivedAt,
            latestGeneratedAt: latest?.report.generatedAt,
            latestReceivedAgeSeconds: latest.map { Int(now.timeIntervalSince($0.receivedAt)) },
            latestGeneratedAgeSeconds: latest.map { Int(now.timeIntervalSince($0.report.generatedAt)) },
            deviceName: latest?.report.deviceName,
            remoteAddress: latest?.remoteAddress
        )
    }
}

private struct AgentHealthContext: Encodable {
    var status: BridgeStatusPayload
    var dataWindow: AgentDataWindow
    var today: DailyHealthSummary?
    var latestCompleteDay: DailyHealthSummary?
    var dailySummaries: [DailyHealthSummary]
    var aggregates: AgentHealthAggregates
    var sampleTypes: [AgentSampleTypeSummary]
    var recentSamples: [HealthSample]
    var availableEndpoints: [String: String]
    var agentNotes: [String]

    static func make(from latest: StoredHealthReport, days: Int, sampleLimit: Int) -> AgentHealthContext {
        let summaries = filteredDailySummaries(latest.report.dailySummaries, days: days)
        let todayString = DateFormatter.healthBridgeDay.string(from: Date())
        let today = summaries.last { $0.date == todayString }
        let latestCompleteDay = summaries.reversed().first { $0.date != todayString }

        return AgentHealthContext(
            status: BridgeStatusPayload.make(from: latest),
            dataWindow: AgentDataWindow.make(requestedDays: days, summaries: summaries),
            today: today,
            latestCompleteDay: latestCompleteDay,
            dailySummaries: summaries,
            aggregates: AgentHealthAggregates.make(from: summaries),
            sampleTypes: AgentSampleTypeSummary.make(from: latest.report.samples),
            recentSamples: makeRecentSamples(from: latest.report.samples, type: nil, limit: sampleLimit),
            availableEndpoints: [
                "status": "\(HealthBridgeConstants.agentBaseURL)/v1/status",
                "agentContext": "\(HealthBridgeConstants.agentBaseURL)/v1/agent/context?days=14&sampleLimit=20",
                "dailySummaries": "\(HealthBridgeConstants.agentBaseURL)/v1/summary/daily?days=14",
                "recentHeartRateSamples": "\(HealthBridgeConstants.agentBaseURL)/v1/samples/recent?type=heartRate&limit=50",
                "latestFullReport": "\(HealthBridgeConstants.agentBaseURL)/v1/report/latest",
                "openapi": "\(HealthBridgeConstants.agentBaseURL)/v1/openapi.json"
            ],
            agentNotes: [
                "Use latestCompleteDay and dailySummaries for health planning; today can be partial.",
                "All timestamps are ISO 8601. Daily date strings use the Mac local calendar.",
                "Local requests from 127.0.0.1 do not require a bearer token; Tailscale or LAN requests require Authorization: Bearer \(HealthBridgeConstants.sharedToken)."
            ]
        )
    }
}

private struct AgentDataWindow: Encodable {
    var requestedDays: Int
    var availableDays: Int
    var startDate: String?
    var endDate: String?

    static func make(requestedDays: Int, summaries: [DailyHealthSummary]) -> AgentDataWindow {
        AgentDataWindow(
            requestedDays: requestedDays,
            availableDays: summaries.count,
            startDate: summaries.first?.date,
            endDate: summaries.last?.date
        )
    }
}

private struct AgentHealthAggregates: Encodable {
    var days: Int
    var totalSteps: Double?
    var averageDailySteps: Double?
    var totalWalkingRunningDistanceKilometers: Double?
    var averageDailyWalkingRunningDistanceKilometers: Double?
    var totalActiveEnergyKilocalories: Double?
    var averageDailyActiveEnergyKilocalories: Double?
    var totalExerciseMinutes: Double?
    var averageDailyExerciseMinutes: Double?
    var averageSleepHours: Double?
    var averageHeartRateBPM: Double?
    var averageRestingHeartRateBPM: Double?
    var latestBodyMassKilograms: Double?

    static func make(from summaries: [DailyHealthSummary]) -> AgentHealthAggregates {
        let distanceMeters = summaries.map(\.walkingRunningDistanceMeters)
        let sleepMinutes = summaries.map(\.sleepAsleepMinutes)

        return AgentHealthAggregates(
            days: summaries.count,
            totalSteps: sum(summaries.map(\.stepCount)),
            averageDailySteps: average(summaries.map(\.stepCount)),
            totalWalkingRunningDistanceKilometers: sum(distanceMeters).map { $0 / 1_000 },
            averageDailyWalkingRunningDistanceKilometers: average(distanceMeters).map { $0 / 1_000 },
            totalActiveEnergyKilocalories: sum(summaries.map(\.activeEnergyKilocalories)),
            averageDailyActiveEnergyKilocalories: average(summaries.map(\.activeEnergyKilocalories)),
            totalExerciseMinutes: sum(summaries.map(\.exerciseMinutes)),
            averageDailyExerciseMinutes: average(summaries.map(\.exerciseMinutes)),
            averageSleepHours: average(sleepMinutes).map { $0 / 60 },
            averageHeartRateBPM: average(summaries.map(\.heartRateAverageBPM)),
            averageRestingHeartRateBPM: average(summaries.map(\.restingHeartRateAverageBPM)),
            latestBodyMassKilograms: latestNonNil(summaries.map(\.bodyMassKilograms))
        )
    }
}

private struct AgentSampleTypeSummary: Encodable {
    var type: String
    var count: Int
    var unit: String
    var latestEndDate: Date?
    var latestValue: Double?
    var sources: [String]

    static func make(from samples: [HealthSample]) -> [AgentSampleTypeSummary] {
        Dictionary(grouping: samples, by: \.type)
            .keys
            .sorted()
            .compactMap { type in
                guard let group = Dictionary(grouping: samples, by: \.type)[type] else {
                    return nil
                }
                let latest = group.max { $0.endDate < $1.endDate }
                let sources = Set(group.compactMap(\.sourceName)).sorted()
                return AgentSampleTypeSummary(
                    type: type,
                    count: group.count,
                    unit: latest?.unit ?? group.first?.unit ?? "",
                    latestEndDate: latest?.endDate,
                    latestValue: latest?.value,
                    sources: sources
                )
            }
    }
}

private func filteredDailySummaries(_ summaries: [DailyHealthSummary], days: Int?) -> [DailyHealthSummary] {
    let sorted = summaries.sorted { $0.date < $1.date }
    guard let days else {
        return sorted
    }
    return Array(sorted.suffix(days))
}

private func makeRecentSamples(from samples: [HealthSample], type: String?, limit: Int) -> [HealthSample] {
    guard limit > 0 else {
        return []
    }

    let filtered = samples.filter { sample in
        guard let type, !type.isEmpty else {
            return true
        }
        return sample.type == type
    }
    return Array(filtered.sorted { $0.endDate > $1.endDate }.prefix(limit))
}

private func sum(_ values: [Double?]) -> Double? {
    let presentValues = values.compactMap { $0 }
    guard !presentValues.isEmpty else {
        return nil
    }
    return presentValues.reduce(0, +)
}

private func average(_ values: [Double?]) -> Double? {
    let presentValues = values.compactMap { $0 }
    guard !presentValues.isEmpty else {
        return nil
    }
    return presentValues.reduce(0, +) / Double(presentValues.count)
}

private func latestNonNil(_ values: [Double?]) -> Double? {
    values.reversed().compactMap { $0 }.first
}

private struct OpenAPIDocument: Encodable {
    var openapi: String
    var info: [String: String]
    var paths: [String: [String: Endpoint]]

    struct Endpoint: Encodable {
        var summary: String
    }

    static func make() -> OpenAPIDocument {
        OpenAPIDocument(
            openapi: "3.1.0",
            info: [
                "title": "Health Agent Bridge",
                "version": "1.0.0"
            ],
            paths: [
                "/v1/status": ["get": Endpoint(summary: "Return bridge status and latest sync timestamps")],
                "/v1/agent/context": ["get": Endpoint(summary: "Return compact agent-oriented health context. Query: days, sampleLimit")],
                "/v1/summary/daily": ["get": Endpoint(summary: "Return daily health summaries from the latest report. Query: days")],
                "/v1/samples/recent": ["get": Endpoint(summary: "Return recent raw samples sorted by newest first. Query: type, limit")],
                "/v1/report/latest": ["get": Endpoint(summary: "Return the latest full health report")],
                "/v1/ingest": ["post": Endpoint(summary: "Receive a health report from the paired iPhone app")]
            ]
        )
    }
}

private extension Data {
    func firstRange(in data: Data) -> Range<Data.Index>? {
        data.range(of: self)
    }
}

private extension JSONEncoder {
    func dateEncodingStrategyDescription(for date: Date) -> String {
        let data = (try? encode(["date": date])) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text
            .replacingOccurrences(of: "{\n  \"date\" : \"", with: "")
            .replacingOccurrences(of: "\"\n}", with: "")
            .replacingOccurrences(of: "{\"date\":\"", with: "")
            .replacingOccurrences(of: "\"}", with: "")
    }
}
