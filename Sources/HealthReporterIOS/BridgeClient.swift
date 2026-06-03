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

    private func send(body: Data, to endpoint: NWEndpoint, hostHeader: String, timeout: TimeInterval = 10) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let connection = NWConnection(to: endpoint, using: .tcp)
            var didFinish = false
            var responseBuffer = Data()
            var timeoutWorkItem: DispatchWorkItem?

            func finish(_ result: Result<Void, Error>) {
                guard !didFinish else { return }
                didFinish = true
                timeoutWorkItem?.cancel()
                connection.cancel()
                switch result {
                case .success:
                    continuation.resume()
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

                    if let statusCode = HTTPClientResponse.statusCode(from: responseBuffer) {
                        if (200..<300).contains(statusCode) {
                            finish(.success(()))
                        } else {
                            finish(.failure(BridgeClientError.sendFailed("Mac 返回 HTTP \(statusCode)")))
                        }
                    } else if isComplete {
                        finish(.failure(BridgeClientError.invalidResponse("没有收到完整 HTTP 状态行")))
                    } else {
                        readResponse()
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let requestHead = """
                    POST \(HealthBridgeConstants.ingestPath) HTTP/1.1\r
                    Host: \(hostHeader)\r
                    Content-Type: application/json\r
                    Authorization: Bearer \(HealthBridgeConstants.sharedToken)\r
                    Content-Length: \(body.count)\r
                    Connection: close\r
                    \r

                    """
                    var payload = Data(requestHead.utf8)
                    payload.append(body)
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
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = data[..<headerRange.lowerBound]
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
}
