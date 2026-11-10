import Foundation

/// Minimal MQTT 3.1.1 encoder/decoder — just the subset the VIDAA broker needs.
struct MQTTPacket {
    enum Kind: UInt8 {
        case connect = 1, connack = 2, publish = 3, puback = 4
        case subscribe = 8, suback = 9, pingreq = 12, pingresp = 13, disconnect = 14
    }

    /// Remaining-length varint (7 bits per byte, high bit = continuation).
    static func encodeLength(_ n: Int) -> [UInt8] {
        var value = n
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(value % 128)
            value /= 128
            if value > 0 { byte |= 0x80 }
            out.append(byte)
        } while value > 0
        return out
    }

    /// Length-prefixed UTF-8 string.
    static func encodeString(_ s: String) -> [UInt8] {
        let bytes = Array(s.utf8)
        return [UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)] + bytes
    }

    static func connect(clientId: String, username: String, password: String,
                        keepAlive: UInt16 = 60) -> Data {
        var payload: [UInt8] = []
        // Protocol name "MQTT", version 4 (3.1.1)
        payload += encodeString("MQTT")
        payload += [4]
        // Connect flags: username | password | clean session
        payload += [0b1100_0010]
        payload += [UInt8(keepAlive >> 8), UInt8(keepAlive & 0xFF)]

        for field in [clientId, username, password] {
            payload += encodeString(field)
        }

        return Data([0x10] + encodeLength(payload.count) + payload)
    }

    static func subscribe(topics: [String], packetId: UInt16) -> Data {
        var payload: [UInt8] = [UInt8(packetId >> 8), UInt8(packetId & 0xFF)]
        for topic in topics {
            payload += encodeString(topic)
            payload += [0]  // QoS 0
        }
        return Data([0x82] + encodeLength(payload.count) + payload)
    }

    static func publish(topic: String, payload: String, retain: Bool = false) -> Data {
        var body = encodeString(topic)
        body += Array(payload.utf8)
        let header: UInt8 = 0x30 | (retain ? 0x01 : 0x00)
        return Data([header] + encodeLength(body.count) + body)
    }

    static let pingreq = Data([0xC0, 0x00])
    static let disconnect = Data([0xE0, 0x00])

    /// SUBACK: fixed header + packet id + one return code per topic.
    /// Returns the granted return codes so failed subscriptions can be detected
    /// (the VIDAA broker rejects wildcards with 0x80).
    static func parseSuback(_ packet: Incoming) -> [UInt8] {
        guard packet.kind == Kind.suback.rawValue, packet.body.count >= 2 else { return [] }
        return Array(packet.body.dropFirst(2))
    }

    /// Parsed inbound packet.
    struct Incoming {
        let kind: UInt8
        let flags: UInt8
        let body: [UInt8]

        var topic: String? {
            guard kind == 3, body.count >= 2 else { return nil }
            let topicLength = Int(body[0]) << 8 | Int(body[1])
            guard 2 + topicLength <= body.count else { return nil }
            return String(decoding: body[2..<(2 + topicLength)], as: UTF8.self)
        }

        var payload: String? {
            guard kind == 3, body.count >= 2 else { return nil }
            let topicLength = Int(body[0]) << 8 | Int(body[1])
            let start = 2 + topicLength
            // QoS 0 has no packet identifier.
            guard start <= body.count else { return nil }
            var offset = start
            let qos = (flags >> 1) & 0x03
            if qos > 0 { offset += 2 }
            guard offset <= body.count else { return "" }
            return String(decoding: body[offset...], as: UTF8.self)
        }
    }
}

/// Incremental MQTT stream framer: accumulates bytes, emits whole packets.
struct MQTTFramer {
    private var buffer: [UInt8] = []

    mutating func append(_ data: Data) {
        buffer += data
    }

    /// Returns every complete packet currently available.
    mutating func drain() -> [MQTTPacket.Incoming] {
        var out: [MQTTPacket.Incoming] = []
        while true {
            guard let (packet, consumed) = MQTTFramer.nextPacket(from: buffer) else { break }
            out.append(packet)
            buffer.removeFirst(consumed)
        }
        return out
    }

    private static func nextPacket(from bytes: [UInt8]) -> (MQTTPacket.Incoming, Int)? {
        guard bytes.count >= 2 else { return nil }

        // Decode the remaining-length varint.
        var multiplier = 1
        var length = 0
        var index = 1
        while true {
            guard index < bytes.count else { return nil }  // incomplete
            let byte = bytes[index]
            length += Int(byte & 0x7F) * multiplier
            multiplier *= 128
            index += 1
            if byte & 0x80 == 0 { break }
            if multiplier > 128 * 128 * 128 { return nil }  // malformed
        }

        let total = index + length
        guard bytes.count >= total else { return nil }

        let header = bytes[0]
        let body = Array(bytes[index..<total])
        return (MQTTPacket.Incoming(kind: header >> 4, flags: header & 0x0F, body: body), total)
    }
}
