import Foundation

actor BridgeStore {
    private let fileURL: URL
    private let packetsFileURL: URL
    private var latest: StoredHealthReport?
    private var packets: [HealthPacket]

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HealthAgentBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        self.fileURL = baseURL.appendingPathComponent("latest-report.json")
        self.packetsFileURL = baseURL.appendingPathComponent("health-packets.json")
        self.latest = try? Self.load(from: fileURL)
        self.packets = (try? Self.loadPackets(from: packetsFileURL)) ?? []
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

    func createPacket(_ request: HealthPacketCreateRequest) throws -> HealthPacket {
        let now = Date()
        let requestedPacketId = request.packetId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let packetId = requestedPacketId?.isEmpty == false
            ? requestedPacketId!
            : "\(request.type.rawValue)-\(UUID().uuidString)"
        guard packets.contains(where: { $0.packetId == packetId }) == false else {
            throw BridgeStoreError.duplicatePacket(packetId)
        }

        switch request.type {
        case .foodIntake:
            guard request.foodIntake != nil else {
                throw BridgeStoreError.invalidPacket("foodIntake payload is required")
            }
        case .bodyWeight:
            guard request.bodyWeight != nil else {
                throw BridgeStoreError.invalidPacket("bodyWeight payload is required")
            }
        }

        let packet = HealthPacket(
            packetId: packetId,
            type: request.type,
            source: request.source ?? .macAPI,
            status: .pendingIOSSync,
            createdAt: now,
            updatedAt: now,
            revision: 1,
            healthKitObjectIds: [],
            lastError: nil,
            foodIntake: request.foodIntake,
            bodyWeight: request.bodyWeight
        )
        packets.append(packet)
        try savePackets()
        return packet
    }

    func pendingPackets(limit: Int) -> [HealthPacket] {
        Array(
            packets
                .filter { $0.status == .pendingIOSSync }
                .sorted { $0.createdAt < $1.createdAt }
                .prefix(limit)
        )
    }

    func recentPackets(limit: Int) -> [HealthPacket] {
        Array(packets.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    func allPackets() -> [HealthPacket] {
        packets
    }

    func acknowledgePacket(packetId: String, request: HealthPacketAcknowledgeRequest) throws -> HealthPacket {
        guard let index = packets.firstIndex(where: { $0.packetId == packetId }) else {
            throw BridgeStoreError.packetNotFound(packetId)
        }

        let updated = packets[index].withUpdatedStatus(
            request.status,
            healthKitObjectIds: request.healthKitObjectIds,
            lastError: request.errorMessage
        )
        packets[index] = updated
        try savePackets()
        return updated
    }

    func updatePacket(packetId: String, request: HealthPacketUpdateRequest) throws -> HealthPacket {
        guard let index = packets.firstIndex(where: { $0.packetId == packetId }) else {
            throw BridgeStoreError.packetNotFound(packetId)
        }

        var packet = packets[index]
        switch packet.type {
        case .foodIntake:
            guard let foodIntake = request.foodIntake else {
                throw BridgeStoreError.invalidPacket("foodIntake payload is required")
            }
            packet.foodIntake = foodIntake
            packet.bodyWeight = nil
        case .bodyWeight:
            guard let bodyWeight = request.bodyWeight else {
                throw BridgeStoreError.invalidPacket("bodyWeight payload is required")
            }
            packet.bodyWeight = bodyWeight
            packet.foodIntake = nil
        }

        packet.status = .pendingIOSSync
        packet.revision += 1
        packet.updatedAt = Date()
        packet.healthKitObjectIds = []
        packet.lastError = nil
        packets[index] = packet
        try savePackets()
        return packet
    }

    private static func load(from url: URL) throws -> StoredHealthReport {
        let data = try Data(contentsOf: url)
        return try JSONCoding.decoder.decode(StoredHealthReport.self, from: data)
    }

    private static func loadPackets(from url: URL) throws -> [HealthPacket] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        return try JSONCoding.decoder.decode([HealthPacket].self, from: data)
    }

    private func savePackets() throws {
        let data = try JSONCoding.encoder.encode(packets)
        try data.write(to: packetsFileURL, options: [.atomic])
    }
}

enum BridgeStoreError: LocalizedError {
    case duplicatePacket(String)
    case invalidPacket(String)
    case packetNotFound(String)

    var errorDescription: String? {
        switch self {
        case .duplicatePacket(let packetId):
            return "Packet already exists: \(packetId)"
        case .invalidPacket(let message):
            return "Invalid packet: \(message)"
        case .packetNotFound(let packetId):
            return "Packet not found: \(packetId)"
        }
    }
}
