import CoreMIDI
import Foundation

setbuf(stdout, nil)

var client = MIDIClientRef()
MIDIClientCreate("bvtester" as CFString, nil, nil, &client)

// Virtual destination: receives whatever the app sends to "all destinations".
var dest = MIDIEndpointRef()
MIDIDestinationCreateWithBlock(client, "BVLED" as CFString, &dest) { packetList, _ in
    var packet = packetList.pointee.packet
    for _ in 0..<packetList.pointee.numPackets {
        let length = Int(packet.length)
        let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(length)) }
        print("LED recv \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
        packet = MIDIPacketNext(&packet).pointee
    }
}

// Virtual source: the fake pad controller (created AFTER app launch → hot-plug).
var source = MIDIEndpointRef()
MIDISourceCreateWithProtocol(client, "BVPad" as CFString, ._1_0, &source)
print("tester: virtual endpoints up")

// Loopback check: listen to our own virtual source through a protocol port.
var selfPort = MIDIPortRef()
MIDIInputPortCreateWithProtocol(client, "selfin" as CFString, ._1_0, &selfPort) { eventList, _ in
    print("SELF recv packets=\(eventList.pointee.numPackets)")
}
let selfConnect = MIDIPortConnectSource(selfPort, source, nil)
print("tester: self-connect status=\(selfConnect)")

// MIDI-1.0-in-UMP words: 0x2 message type, group 0, then the classic 3 bytes.
func send(_ words: [UInt32]) {
    var eventList = MIDIEventList()
    let packet = MIDIEventListInit(&eventList, ._1_0)
    let added = MIDIEventListAdd(
        &eventList, MemoryLayout<MIDIEventList>.size, packet, 0, words.count, words
    )
    let status = MIDIReceivedEventList(source, &eventList)
    print("tester: sent status=\(status) added=\(added != nil ? "ok" : "FAIL")")
}

Thread.sleep(forTimeInterval: 1.5)
print("tester: noteOn 60 (rate3)")
send([0x2090_3C64])
Thread.sleep(forTimeInterval: 0.8)
print("tester: noteOff 60 (Q3 -> expect re-assert ON)")
send([0x2080_3C00])
Thread.sleep(forTimeInterval: 0.8)
print("tester: noteOn 62 (keyword)")
send([0x2090_3E64])
Thread.sleep(forTimeInterval: 0.8)
print("tester: CC then noteOn 63 in one packet (C9)")
send([0x20B0_0764, 0x2090_3F64])
Thread.sleep(forTimeInterval: 1.5)
print("tester: done")
