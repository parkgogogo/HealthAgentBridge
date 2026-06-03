import Foundation
import Network

enum BridgeClientError: LocalizedError {
    case discoveryTimedOut
    case connectionFailed(String)
    case sendFailed(String)
    case invalidResponse(String)
    case allEndpointsFailed(tailnet: String, bonjour: String)

    var errorDescription: String? {
        switch self {
        case .discoveryTimedOut:
            return "未发现 Mac 健康桥接服务"
        case .connectionFailed(let message):
            return "连接 Mac 失败：\(message)"
        case .sendFailed(let message):
            return "上报失败：\(message)"
        case .invalidResponse(let message):
            return "Mac 响应异常：\(message)"
        case .allEndpointsFailed(let tailnet, let bonjour):
            return "Tailscale 连接失败：\(tailnet)；Bonjour 备用失败：\(bonjour)"
        }
    }
}

struct BridgeUploadResult {
    var endpointDescription: String
}

struct BridgePacketSyncResult {
    var endpointDescription: String
}

final class BridgeClient {
    private let queue = DispatchQueue(label: "HealthReporter.BridgeClient")

    func upload(_ report: HealthReportEnvelope) async throws -> BridgeUploadResult {
        let body = try JSONCoding.encoder.encode(report)

        var tailnetErrors: [String] = []
        for target in tailnetTargets {
            do {
                let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(target.host), port: bridgePort)
                try await send(
                    body: body,
                    to: endpoint,
                    hostHeader: "\(target.host):\(HealthBridgeConstants.port)"
                )
                return BridgeUploadResult(endpointDescription: "\(target.label)：\(target.host):\(HealthBridgeConstants.port)")
            } catch {
                tailnetErrors.append("\(target.label) \(target.host): \(error.localizedDescription)")
            }
        }

        do {
            let endpoint = try await discoverEndpoint()
            try await send(body: body, to: endpoint, hostHeader: "health-agent-bridge")
            return BridgeUploadResult(endpointDescription: "Bonjour：\(endpointDescription(for: endpoint))")
        } catch let bonjourError {
            throw BridgeClientError.allEndpointsFailed(
                tailnet: tailnetErrors.joined(separator: "；"),
                bonjour: bonjourError.localizedDescription
            )
        }
    }

    func fetchPendingPackets(limit: Int = 50) async throws -> [HealthPacket] {
        let path = "/v1/packets/pending?limit=\(limit)"
        let data = try await request(method: "GET", path: path, body: nil)
        return try JSONCoding.decoder.decode(HealthPacketListPayload.self, from: data).packets
    }

    func fetchRecentPackets(limit: Int = 50) async throws -> [HealthPacket] {
        let path = "/v1/packets/recent?limit=\(limit)"
        let data = try await request(method: "GET", path: path, body: nil)
        return try JSONCoding.decoder.decode(HealthPacketListPayload.self, from: data).packets
    }

    func updatePacket(packetId: String, request updateRequest: HealthPacketUpdateRequest) async throws -> HealthPacket {
        let body = try JSONCoding.encoder.encode(updateRequest)
        let path = "/v1/packets/\(packetId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? packetId)"
        let data = try await request(method: "PUT", path: path, body: body)
        return try JSONCoding.decoder.decode(HealthPacket.self, from: data)
    }

    func acknowledgePacket(packetId: String, request: HealthPacketAcknowledgeRequest) async throws -> BridgePacketSyncResult {
        let body = try JSONCoding.encoder.encode(request)
        let path = "/v1/packets/\(packetId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? packetId)/ack"
        let result = try await requestWithEndpointDescription(method: "POST", path: path, body: body)
        return BridgePacketSyncResult(endpointDescription: result.endpointDescription)
    }

    private var bridgePort: NWEndpoint.Port {
        NWEndpoint.Port(rawValue: HealthBridgeConstants.port)!
    }

    private var tailnetTargets: [(label: String, host: String)] {
        [
            ("Tailscale MagicDNS", HealthBridgeConstants.tailnetHost),
            ("Tailscale IPv4", HealthBridgeConstants.tailnetIPv4)
        ]
    }

    private func discoverEndpoint(timeout: TimeInterval = 8) async throws -> NWEndpoint {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWEndpoint, Error>) in
            let browser = NWBrowser(
                for: .bonjour(type: HealthBridgeConstants.bonjourType, domain: nil),
                using: .tcp
            )
            var didFinish = false

            func finish(_ result: Result<NWEndpoint, Error>) {
                guard !didFinish else { return }
                didFinish = true
                browser.cancel()
                switch result {
                case .success(let endpoint):
                    continuation.resume(returning: endpoint)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            browser.browseResultsChangedHandler = { results, _ in
                guard let endpoint = results.first?.endpoint else { return }
                finish(.success(endpoint))
            }

            browser.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    finish(.failure(BridgeClientError.connectionFailed(error.localizedDescription)))
                }
            }

            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(BridgeClientError.discoveryTimedOut))
            }
        }
    }

    private func request(method: String, path: String, body: Data?) async throws -> Data {
        try await requestWithEndpointDescription(method: method, path: path, body: body).data
    }

    private func requestWithEndpointDescription(method: String, path: String, body: Data?) async throws -> (data: Data, endpointDescription: String) {
        var tailnetErrors: [String] = []
        for target in tailnetTargets {
            do {
                let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(target.host), port: bridgePort)
                let data = try await sendRequest(
                    method: method,
                    path: path,
                    body: body,
                    to: endpoint,
                    hostHeader: "\(target.host):\(HealthBridgeConstants.port)"
                )
                return (data, "\(target.label)：\(target.host):\(HealthBridgeConstants.port)")
            } catch {
                tailnetErrors.append("\(target.label) \(target.host): \(error.localizedDescription)")
            }
        }

        do {
            let endpoint = try await discoverEndpoint()
            let data = try await sendRequest(
                method: method,
                path: path,
                body: body,
                to: endpoint,
                hostHeader: "health-agent-bridge"
            )
            return (data, "Bonjour：\(endpointDescription(for: endpoint))")
        } catch let bonjourError {
            throw BridgeClientError.allEndpointsFailed(
                tailnet: tailnetErrors.joined(separator: "；"),
                bonjour: bonjourError.localizedDescription
            )
        }
    }

    private func send(body: Data, to endpoint: NWEndpoint, hostHeader: String, timeout: TimeInterval = 10) async throws {
        _ = try await sendRequest(
            method: "POST",
            path: HealthBridgeConstants.ingestPath,
            body: body,
            to: endpoint,
            hostHeader: hostHeader,
            timeout: timeout
        )
    }

    private func sendRequest(
        method: String,
        path: String,
        body: Data?,
        to endpoint: NWEndpoint,
        hostHeader: String,
        timeout: TimeInterval = 10
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let connection = NWConnection(to: endpoint, using: .tcp)
            var didFinish = false
            var responseBuffer = Data()
            var timeoutWorkItem: DispatchWorkItem?

            func finish(_ result: Result<Data, Error>) {
                guard !didFinish else { return }
                didFinish = true
                timeoutWorkItem?.cancel()
                connection.cancel()
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            func readResponse() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    if let error {
                        finish(.failure(BridgeClientError.connectionFailed(error.localizedDescription)))
                        return
                    }

                    if let data {
                        responseBuffer.append(data)
                    }

                    if let statusCode = HTTPClientResponse.statusCode(from: responseBuffer),
                       let bodyData = HTTPClientResponse.bodyData(from: responseBuffer) {
                        if (200..<300).contains(statusCode) {
                            finish(.success(bodyData))
                        } else {
                            let message = String(data: bodyData, encoding: .utf8) ?? "Mac 返回 HTTP \(statusCode)"
                            finish(.failure(BridgeClientError.sendFailed(message)))
                        }
                    } else if isComplete {
                        finish(.failure(BridgeClientError.invalidResponse("没有收到完整 HTTP 响应")))
                    } else {
                        readResponse()
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let requestBody = body ?? Data()
                    let requestHead = """
                    \(method) \(path) HTTP/1.1\r
                    Host: \(hostHeader)\r
                    Content-Type: application/json\r
                    Authorization: Bearer \(HealthBridgeConstants.sharedToken)\r
                    Content-Length: \(requestBody.count)\r
                    Connection: close\r
                    \r

                    """
                    var payload = Data(requestHead.utf8)
                    payload.append(requestBody)
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error {
                            finish(.failure(BridgeClientError.sendFailed(error.localizedDescription)))
                        } else {
                            readResponse()
                        }
                    })
                case .failed(let error):
                    finish(.failure(BridgeClientError.connectionFailed(error.localizedDescription)))
                case .cancelled:
                    break
                default:
                    break
                }
            }

            connection.start(queue: queue)
            let workItem = DispatchWorkItem {
                finish(.failure(BridgeClientError.connectionFailed("请求超时")))
            }
            timeoutWorkItem = workItem
            queue.asyncAfter(deadline: .now() + timeout, execute: workItem)
        }
    }

    private func endpointDescription(for endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        case .service(let name, _, _, _):
            return name
        case .unix:
            return "unix"
        case .url(let url):
            return url.absoluteString
        case .opaque:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }
}

private enum HTTPClientResponse {
    static func statusCode(from data: Data) -> Int? {
        guard let headerData = headerData(from: data) else { return nil }
        guard let headerText = String(data: headerData, encoding: .utf8),
              let statusLine = headerText.components(separatedBy: "\r\n").first else {
            return nil
        }

        let parts = statusLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            return nil
        }

        return Int(parts[1])
    }

    static func bodyData(from data: Data) -> Data? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let bodyStart = headerRange.upperBound
        let availableBodyLength = data.count - bodyStart
        if let contentLength = contentLength(from: data), availableBodyLength < contentLength {
            return nil
        }

        if let contentLength = contentLength(from: data) {
            return Data(data[bodyStart..<(bodyStart + contentLength)])
        }
        return Data(data[bodyStart...])
    }

    private static func headerData(from data: Data) -> Data? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        return Data(data[..<headerRange.lowerBound])
    }

    private static func contentLength(from data: Data) -> Int? {
        guard let headerData = headerData(from: data),
              let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key == "content-length" else { continue }
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(value)
        }
        return nil
    }
}
