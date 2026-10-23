import ARKit
import Foundation

final class Tracker: NSObject, ObservableObject, ARSessionDelegate {
    @Published var host = "play.rossklein.com"
    @Published var room = "play"
    @Published var token = "dev"
    @Published var status = "Idle"
    @Published var detail = "The back camera has to see the room. LiDAR is used when this phone has it."
    @Published var running = false
    @Published var canStop = true

    let session = ARSession()

    private var socket: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var seq: UInt32 = 1
    private var offsetMs = 0.0
    private var synced = false
    private var origin: SIMD3<Float>?
    private var lastSent = Date.distantPast
    private var pings: [(rtt: Double, offset: Double)] = []
    private let lidar = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)

    override init() {
        super.init()
        session.delegate = self
    }

    func toggle() {
        if running {
            stop()
        } else {
            start()
        }
    }

    func resetOrigin() {
        origin = nil
    }

    private func start() {
        origin = nil
        synced = false
        seq = 1
        connect()
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = [.horizontal, .vertical]
        if lidar {
            config.frameSemantics.insert(.sceneDepth)
        }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        running = true
        status = lidar ? "LiDAR tracking" : "Camera tracking"
    }

    private func stop() {
        pingTimer?.invalidate()
        pingTimer = nil
        session.pause()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        running = false
        synced = false
        status = "Stopped"
    }

    private func connect() {
        guard let url = relayURL() else {
            status = "Bad server address"
            return
        }
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        listen()
        sendPing()
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func relayURL() -> URL? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = "role=phone&room=\(escape(room))&token=\(escape(token))"
        if trimmed.contains("://") {
            return URL(string: "\(trimmed)/ws?\(query)")
        }
        let isName = trimmed.rangeOfCharacter(from: .letters) != nil && !trimmed.contains(":")
        if isName {
            return URL(string: "wss://\(trimmed)/ws?\(query)")
        }
        let authority = trimmed.contains(":") ? trimmed : "\(trimmed):8787"
        return URL(string: "ws://\(authority)/ws?\(query)")
    }

    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private func listen() {
        socket?.receive { [weak self] result in
            guard let self, self.socket != nil else { return }
            if case .failure = result { return }
            if case .success(let message) = result, case .data(let data) = message {
                self.notePong(data)
            }
            self.listen()
        }
    }

    private func sendPing() {
        let sent = Date().timeIntervalSince1970 * 1000
        var data = Data([2])
        appendFloat64(sent, to: &data)
        socket?.send(.data(data)) { _ in }
    }

    private func notePong(_ data: Data) {
        guard data.count >= 17, data[0] == 3 else { return }
        let sent = readFloat64(data, 1)
        let server = readFloat64(data, 9)
        let now = Date().timeIntervalSince1970 * 1000
        let rtt = now - sent
        guard rtt >= 0, rtt < 5000 else { return }
        pings.append((rtt, server - (sent + rtt / 2)))
        if pings.count > 8 { pings.removeFirst() }
        let best = pings.min { $0.rtt < $1.rtt } ?? pings[0]
        offsetMs = best.offset
        synced = true
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = Date()
        guard synced, now.timeIntervalSince(lastSent) >= 1.0 / 30 else { return }
        switch frame.camera.trackingState {
        case .normal, .limited:
            break
        case .notAvailable:
            return
        }
        lastSent = now
        let transform = frame.camera.transform
        var position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        if origin == nil { origin = position }
        position -= origin ?? .zero
        let rotation = simd_quatf(transform)
        sendPose(position: position, rotation: rotation)
        let meters = String(format: "%.2f  %.2f  %.2f", position.x, position.y, position.z)
        DispatchQueue.main.async {
            self.detail = "Room position \(meters) m"
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let text: String
        switch camera.trackingState {
        case .normal:
            text = lidar ? "Tracking, LiDAR on" : "Tracking"
        case .limited(let reason):
            switch reason {
            case .initializing:
                text = "Limited: initializing"
            case .excessiveMotion:
                text = "Limited: moving too fast"
            case .insufficientFeatures:
                text = "Limited: show more of the room"
            case .relocalizing:
                text = "Limited: finding the room again"
            @unknown default:
                text = "Limited"
            }
        case .notAvailable:
            text = "No tracking yet. Move the phone slowly."
        }
        DispatchQueue.main.async { self.status = text }
    }

    private func sendPose(position: SIMD3<Float>, rotation: simd_quatf) {
        let relayNow = UInt32(truncatingIfNeeded: Int64((Date().timeIntervalSince1970 * 1000) + offsetMs))
        var data = Data(count: 31)
        data[0] = 4
        data[1] = 1
        writeUInt32(seq, data: &data, at: 2)
        writeUInt32(relayNow, data: &data, at: 6)
        seq &+= 1
        let parts = [rotation.real, rotation.imag.x, rotation.imag.y, rotation.imag.z]
        for (index, part) in parts.enumerated() {
            writeInt16(Int16(max(-32767, min(32767, Int(part * 32767)))), data: &data, at: 10 + index * 2)
        }
        writeFloat32(position.x, data: &data, at: 18)
        writeFloat32(position.y, data: &data, at: 22)
        writeFloat32(position.z, data: &data, at: 26)
        data[30] = 2
        socket?.send(.data(data)) { _ in }
    }
}

private func appendFloat64(_ value: Double, to data: inout Data) {
    var bits = value.bitPattern.littleEndian
    withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
}

private func readFloat64(_ data: Data, _ offset: Int) -> Double {
    let bits = data.subdata(in: offset..<(offset + 8)).withUnsafeBytes { $0.load(as: UInt64.self) }
    return Double(bitPattern: UInt64(littleEndian: bits))
}

private func writeUInt32(_ value: UInt32, data: inout Data, at offset: Int) {
    var bits = value.littleEndian
    withUnsafeBytes(of: &bits) { raw in
        data.replaceSubrange(offset..<(offset + 4), with: raw)
    }
}

private func writeInt16(_ value: Int16, data: inout Data, at offset: Int) {
    var bits = value.littleEndian
    withUnsafeBytes(of: &bits) { raw in
        data.replaceSubrange(offset..<(offset + 2), with: raw)
    }
}

private func writeFloat32(_ value: Float, data: inout Data, at offset: Int) {
    var bits = value.bitPattern.littleEndian
    withUnsafeBytes(of: &bits) { raw in
        data.replaceSubrange(offset..<(offset + 4), with: raw)
    }
}
