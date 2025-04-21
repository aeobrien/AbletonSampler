import Foundation
import CoreMIDI
import Combine // Needed for ObservableObject
import os.log // For logging

// MARK: - MIDI Device Information Struct

struct MIDIDeviceInfo: Identifiable, Hashable {
    var id: MIDIEndpointRef // CoreMIDI's reference for the endpoint, stable enough for Identifiable
    var name: String
    var isVirtual: Bool = false // Flag to indicate if it's a virtual device/port created by this app
}

// MARK: - MIDI Manager Class

class MIDIManager: ObservableObject {
    // MARK: - Published Properties for SwiftUI
    @Published var midiSources: [MIDIDeviceInfo] = []
    @Published var midiDestinations: [MIDIDeviceInfo] = []
    @Published var connectedSourceIDs: Set<MIDIEndpointRef> = [] // Track connected sources
    @Published var lastReceivedNoteNumber: Int? = nil // Store the last received MIDI note number

    // MARK: - CoreMIDI Properties
    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0 // Port for receiving MIDI data
    private var outputPort: MIDIPortRef = 0 // Port for sending MIDI data

    // Logger for debugging
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.AbletonSampler", category: "MIDIManager")

    // MARK: - Initialization and Teardown

    init() {
        logger.info("MIDIManager Initializing...")
        setupMIDI()
    }

    deinit {
        logger.info("MIDIManager Deinitializing...")
        tearDownMIDI()
    }

    // MARK: - CoreMIDI Setup

    private func setupMIDI() {
        logger.debug("Setting up CoreMIDI client and ports.")

        // --- Create MIDI Client ---
        // We use MIDIClientCreateWithBlock for notifications
        let statusClient = MIDIClientCreateWithBlock("AbletonSamplerMIDIClient" as CFString, &midiClient) { [weak self] notificationPtr in
            self?.handleMIDISetupNotification(notificationPtr)
        }

        guard statusClient == noErr else {
            logger.error("Error creating MIDI client: \(statusClient)")
            return
        }
        logger.info("MIDI Client created successfully.")

        // --- Create Input Port ---
        // We use MIDIInputPortCreateWithBlock to handle incoming MIDI packets
        let statusInputPort = MIDIInputPortCreateWithBlock(midiClient, "AbletonSamplerInputPort" as CFString, &inputPort) { [weak self] packetListPtr, srcConnRefCon in
            self?.handleMIDIPackets(packetListPtr, srcConnRefCon: srcConnRefCon)
        }

        guard statusInputPort == noErr else {
            logger.error("Error creating MIDI input port: \(statusInputPort)")
            // Consider partial cleanup if client creation succeeded but port failed
            MIDIClientDispose(midiClient) // Clean up the client if port creation fails
            midiClient = 0
            return
        }
        logger.info("MIDI Input Port created successfully.")


        // --- Create Output Port ---
        let statusOutputPort = MIDIOutputPortCreate(midiClient, "AbletonSamplerOutputPort" as CFString, &outputPort)
        guard statusOutputPort == noErr else {
            logger.error("Error creating MIDI output port: \(statusOutputPort)")
            // Consider partial cleanup
            MIDIPortDispose(self.inputPort)
            MIDIClientDispose(midiClient) // Dispose client
            midiClient = 0
            self.inputPort = 0 // Already had self. here, keep for clarity
            return
        }
        logger.info("MIDI Output Port created successfully.")


        // --- Initial Device Scan ---
        logger.debug("Performing initial scan for MIDI devices.")
        refreshDevices() // Populate initial lists
    }

    // MARK: - CoreMIDI Teardown

    private func tearDownMIDI() {
        logger.debug("Tearing down CoreMIDI resources.")
        var result: OSStatus

        // Dispose of the input port
        if inputPort != 0 {
            // --- Disconnect all sources before disposing port ---
            logger.debug("Disconnecting all sources from input port \(self.inputPort).")
            let currentSources = MIDIGetNumberOfSources()
            for i in 0..<currentSources {
                let sourceEndpoint = MIDIGetSource(i)
                if connectedSourceIDs.contains(sourceEndpoint) { // Check if we were connected
                    let disconnectStatus = MIDIPortDisconnectSource(self.inputPort, sourceEndpoint)
                    if disconnectStatus == noErr {
                        logger.info("Successfully disconnected source \(sourceEndpoint) during teardown.")
                    } else {
                         // Log error but continue teardown
                        logger.error("Error disconnecting source \(sourceEndpoint) during teardown: \(disconnectStatus)")
                    }
                }
            }
            // ---------------------------------------------------

            result = MIDIPortDispose(inputPort)
            if result == noErr {
                logger.info("Successfully disposed MIDI Input Port.")
                inputPort = 0
            } else {
                logger.error("Error disposing MIDI Input Port: \(result)")
            }
        }

        // Dispose of the output port
        if outputPort != 0 {
            result = MIDIPortDispose(outputPort)
            if result == noErr {
                logger.info("Successfully disposed MIDI Output Port.")
                outputPort = 0
            } else {
                logger.error("Error disposing MIDI Output Port: \(result)")
            }
        }

        // Dispose of the MIDI client
        if midiClient != 0 {
            result = MIDIClientDispose(midiClient)
            if result == noErr {
                logger.info("Successfully disposed MIDI Client.")
                midiClient = 0
            } else {
                logger.error("Error disposing MIDI Client: \(result)")
            }
        }
    }

    // MARK: - Device Handling and Refreshing

    /// Refreshes the lists of MIDI sources and destinations.
    /// Should be called initially and when MIDI setup changes.
    func refreshDevices() {
        logger.debug("Refreshing MIDI device list...")

        // --- Update Sources (Inputs) ---
        var sources: [MIDIDeviceInfo] = []
        let sourceCount = MIDIGetNumberOfSources()
        logger.info("Found \(sourceCount) MIDI sources.")
        for i in 0..<sourceCount {
            let endpoint = MIDIGetSource(i)
            if let deviceInfo = getDeviceInfo(for: endpoint) {
                sources.append(deviceInfo)
                logger.debug("  -> Source [\(i)]: '\(deviceInfo.name)' (ID: \(deviceInfo.id))")
            } else {
                logger.warning("  -> Source [\(i)]: Could not get device info for endpoint \(endpoint)")
            }
        }

        // --- Update Destinations (Outputs) ---
        var destinations: [MIDIDeviceInfo] = []
        let destinationCount = MIDIGetNumberOfDestinations()
        logger.info("Found \(destinationCount) MIDI destinations.")
        for i in 0..<destinationCount {
            let endpoint = MIDIGetDestination(i)
            if let deviceInfo = getDeviceInfo(for: endpoint) {
                destinations.append(deviceInfo)
                 logger.debug("  -> Destination [\(i)]: '\(deviceInfo.name)' (ID: \(deviceInfo.id))")
            } else {
                 logger.warning("  -> Destination [\(i)]: Could not get device info for endpoint \(endpoint)")
            }
        }

        // --- Update Published Properties on Main Thread ---
        // Use DispatchQueue.main.async to ensure UI updates happen on the main thread
        DispatchQueue.main.async { [weak self] in
            self?.midiSources = sources
            self?.midiDestinations = destinations
            self?.logger.debug("Published properties updated on main thread.")
        }
    }

    /// Retrieves display information for a MIDI endpoint.
    /// - Parameter endpoint: The MIDIEndpointRef to query.
    /// - Returns: A MIDIDeviceInfo struct containing the name and ID, or nil if info cannot be retrieved.
    private func getDeviceInfo(for endpoint: MIDIEndpointRef) -> MIDIDeviceInfo? {
        var property: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &property)

        guard status == noErr, let safeProperty = property else {
            logger.error("Error getting display name for endpoint \(endpoint): Status \(status)")
            return nil
        }

        let name = safeProperty.takeRetainedValue() as String
        // Simple check for virtual sources/destinations (often contain app name or "Port")
        // This might need refinement based on specific needs.
        let isVirtual = name.contains("AbletonSampler") // Example check
        return MIDIDeviceInfo(id: endpoint, name: name, isVirtual: isVirtual)
    }


    // MARK: - MIDI Notification Handling

    /// Handles notifications about changes in the MIDI setup (e.g., devices added/removed).
    /// - Parameter notificationPtr: Pointer to the MIDINotification message.
    private func handleMIDISetupNotification(_ notificationPtr: UnsafePointer<MIDINotification>) {
        let notification = notificationPtr.pointee
        logger.info("Received MIDI Setup Notification: ID \(notification.messageID.rawValue)")

        switch notification.messageID {
        case .msgSetupChanged:
            logger.info("MIDI setup changed. Refreshing device list.")
            // It's crucial to refresh the device list when the setup changes.
            refreshDevices()

        case .msgObjectAdded:
            logger.info("MIDI object added. Refreshing device list.")
            // Could potentially get specific info from notification.messageData if needed,
            // but refreshing the whole list is often simplest.
             refreshDevices() // Refresh after adding

        case .msgObjectRemoved:
             logger.info("MIDI object removed. Refreshing device list.")
             // Similar to add, refresh the list.
             refreshDevices() // Refresh after removal

        case .msgPropertyChanged:
            // Often indicates a name change or similar.
            let propChangeInfo = UnsafeRawPointer(notificationPtr).load(as: MIDIObjectPropertyChangeNotification.self)
            // propertyName is non-optional, use takeRetainedValue directly.
            let propertyNameString = propChangeInfo.propertyName.takeRetainedValue() as String
            // Use .rawValue for MIDIObjectType enum
            logger.info("MIDI property changed for object \(propChangeInfo.object) of type \(propChangeInfo.objectType.rawValue) property '\(propertyNameString)'. Refreshing list.")
            refreshDevices() // Refresh on property changes too

        case .msgIOError:
            // Handle I/O errors, possibly by logging or attempting recovery
            let ioErrorInfo = UnsafeRawPointer(notificationPtr).load(as: MIDIIOErrorNotification.self)
            logger.error("MIDI I/O Error Notification for device \(ioErrorInfo.driverDevice). Error code: \(ioErrorInfo.errorCode)")
            // May need to refresh devices or take other action depending on the error

        case .msgSerialPortOwnerChanged, .msgThruConnectionsChanged:
             // Less common, but might still warrant a refresh depending on app logic
             logger.info("Received notification type \(notification.messageID.rawValue). Refreshing device list.")
             refreshDevices()

        @unknown default:
            logger.warning("Received unknown MIDI notification type: \(notification.messageID.rawValue)")
        }
    }

    // MARK: - MIDI Receiving

    /// Callback function invoked by CoreMIDI when MIDI packets are received on the input port.
    /// - Parameters:
    ///   - packetListPtr: Pointer to a MIDIPacketList containing incoming MIDI data.
    ///   - srcConnRefCon: Source connection reference constant (optional user data).
    private func handleMIDIPackets(_ packetListPtr: UnsafePointer<MIDIPacketList>, srcConnRefCon: UnsafeMutableRawPointer?) {
        logger.debug("Received MIDI packet list.")
        // Remove the intermediate variable, iterate directly on the dereferenced pointer's value
        // var packetList = packetListPtr.pointee

        // --- Using Sequence iteration directly on pointee ---
        logger.debug("Iterating packets using Sequence conformance on pointee:")

        // Check if there are any packets to process using the pointer
        guard packetListPtr.pointee.numPackets > 0 else {
            logger.debug("Packet list is empty.")
            return
        }

        // Iterate using the built-in Sequence conformance (yields MIDIPacket)
        // Access pointee directly within the loop declaration
        for (i, packet) in packetListPtr.pointee.enumerated() {
            // Immediately convert to our helper struct
            let packetData = MIDIPacketData(packet: packet)

            // Use the helper struct for easy access
            let bytesString = packetData.data.map { String(format: "%02X", $0) }.joined(separator: " ")
            logger.info("  Packet [\(i)]: time=\(packetData.timestamp.description), len=\(packetData.count), bytes=[\(bytesString)]")

            // Process MIDI data using the helper struct's data array
            if packetData.count > 0 {
                let statusByte = packetData.data[0]
                let command = statusByte & 0xF0 // Mask channel nibble
                let channel = statusByte & 0x0F

                if command == 0x90 && packetData.count >= 3 && packetData.data[2] > 0 { // Note On (velocity > 0)
                    let note = packetData.data[1]
                    let velocity = packetData.data[2]
                    logger.debug("    -> Note On: ch=\(channel + 1), note=\(note), vel=\(velocity)")
                    // --- Update last received note ---
                    DispatchQueue.main.async { [weak self] in
                        // Ensure self is still valid
                        guard let self = self else { return }
                        self.lastReceivedNoteNumber = Int(note)
                        // Add specific logging for this update
                        self.logger.debug("Updated lastReceivedNoteNumber to: \(Int(note)) on main thread.")
                    }
                    // -----------------------------------

                } else if (command == 0x80 || (command == 0x90 && packetData.data[2] == 0)) && packetData.count >= 3 { // Note Off (or Note On with vel 0)
                    let note = packetData.data[1]
                    let velocity = packetData.data[2] // Usually 0 for Note Off, but could be release velocity
                    logger.debug("    -> Note Off: ch=\(channel + 1), note=\(note), vel=\(velocity)")
                    // --- Optionally clear last note on Note Off ---
                    // DispatchQueue.main.async { [weak self] in
                    //     if self?.lastReceivedNoteNumber == Int(note) {
                    //         self?.lastReceivedNoteNumber = nil
                    //     }
                    // }
                    // --- TODO: Trigger action based on Note Off ---

                } else if command == 0xB0 && packetData.count >= 3 { // Control Change (CC)
                    let controller = packetData.data[1]
                    let value = packetData.data[2]
                    logger.debug("    -> CC: ch=\(channel + 1), controller=\(controller), value=\(value)")
                    // --- TODO: Trigger action based on CC ---

                }
                // Add handling for other MIDI message types (Pitch Bend, Program Change, etc.) as needed
            }

            // No need to manually advance pointer when using Sequence conformance
        }
        // -----------------------------------------------------------------------
    }


    // MARK: - MIDI Sending

    /// Sends MIDI data to a specified destination endpoint.
    /// - Parameters:
    ///   - data: An array of `UInt8` bytes representing the MIDI message(s).
    ///   - destination: The `MIDIEndpointRef` of the target device/port.
    func sendMIDIMessage(data: [UInt8], to destination: MIDIEndpointRef) {
        guard outputPort != 0 else {
            logger.error("Cannot send MIDI message: Output port is not initialized.")
            return
        }
        guard !data.isEmpty else {
             logger.warning("Attempted to send empty MIDI message.")
             return
        }

        logger.debug("Attempting to send \(data.count) bytes to endpoint \(destination): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

        // A MIDIPacketList can contain multiple MIDIPackets. For simplicity,
        // we'll create a list containing a single packet here.
        // Max packet size typically around 256 bytes, but check `kMIDIEventListMaxSysexLength` if sending large SysEx.
        let bufferSize = 1024 // Sufficient for typical packet lists
        var packetList = UnsafeMutablePointer<MIDIPacketList>.allocate(capacity: 1) // Allocate memory for the list header + data

        // Get a pointer to the packet data buffer within the allocated memory
        // The actual packets follow the MIDIPacketList header in memory.
        // We need to initialize the first packet *within* this buffer.
        // This requires careful pointer casting and offset calculation.

        // --- Use MIDIPacketListInit and MIDIPacketListAdd ---
        // This is the safer CoreMIDI way to build packet lists.
        let timestamp = MIDITimeStamp(0) // Send immediately (0 = now)

        // Allocate buffer large enough for MIDIPacketList header and our data
        // Size calculation: sizeof(MIDIPacketList) + sizeof(MIDIPacket header) + data.count
        // Simplified: Allocate a reasonable buffer like 256 bytes
        let maxPacketDataSize = 256 // Generous buffer for one packet + header
        var listBuffer = [UInt8](repeating: 0, count: maxPacketDataSize)

        packetList = listBuffer.withUnsafeMutableBytes { bufferPtr -> UnsafeMutablePointer<MIDIPacketList> in
            let listPtr = bufferPtr.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            var currentPacket = MIDIPacketListInit(listPtr) // Initialize the list

            // Add our data as a single packet to the list
            currentPacket = MIDIPacketListAdd(listPtr, // The list pointer
                                             maxPacketDataSize, // Buffer capacity
                                             currentPacket, // Pointer to the current packet position (starts at beginning)
                                             timestamp, // Timestamp for this packet
                                             data.count, // Number of bytes in our MIDI message
                                             data) // The actual MIDI data bytes
            // MIDIPacketListAdd returns the pointer to the *next* available position for a packet,
            // or nil if there isn't enough space. We don't need it here as we add only one packet.
            if currentPacket == nil {
                 logger.error("Failed to add packet to MIDIPacketList (likely buffer too small).")
                 // Need to handle this error case
            }
            return listPtr // Return the initialized list pointer
        }


        // --- Send the Packet List ---
        // Send to the specific destination endpoint
        let sendStatus = MIDISend(outputPort, destination, packetList)

        if sendStatus == noErr {
            logger.info("Successfully sent MIDI message (\(data.count) bytes) to destination \(destination).")
        } else {
            logger.error("Error sending MIDI message to destination \(destination): Status \(sendStatus)")
            // Possible errors include kMIDIUnknownEndpoint if the destination disappeared.
            if sendStatus == kMIDIUnknownEndpoint {
                 logger.warning("Destination endpoint \(destination) no longer exists. Refreshing devices.")
                 refreshDevices()
            }
        }

        // --- Deallocate the buffer ---
        // Since we used `withUnsafeMutableBytes` on a Swift array (`listBuffer`),
        // the memory is managed automatically and does not need manual deallocation here.
        // If we had used `UnsafeMutablePointer<MIDIPacketList>.allocate`, we would need:
        // packetList.deallocate()
    }

    // --- TODO: Add functions to connect/disconnect sources to the input port ---
    // This involves MIDIPortConnectSource / MIDIPortDisconnectSource
    // You'd likely call these when the user selects a source in the UI.

    // MARK: - Source Connection Management

    /// Connects a MIDI source endpoint to the application's input port.
    /// - Parameter source: The `MIDIDeviceInfo` representing the source to connect.
    func connectSource(_ source: MIDIDeviceInfo) {
        guard inputPort != 0 else {
            logger.error("Cannot connect source: Input port is not initialized.")
            return
        }

        logger.info("Attempting to connect source: '\(source.name)' (ID: \(source.id))")
        // The refCon parameter (last one) is user-defined data passed to the MIDIReadProc/Block.
        // We can pass nil if we don't need specific data per connection, or pass a pointer
        // to self or other relevant data if needed.
        let status = MIDIPortConnectSource(inputPort, source.id, nil)

        if status == noErr {
            logger.info("Successfully connected source '\(source.name)'.")
            // Update the set of connected IDs on the main thread
            DispatchQueue.main.async { [weak self] in
                self?.connectedSourceIDs.insert(source.id)
                self?.logger.debug("Updated connectedSourceIDs (added \(source.id)). Current: \(self?.connectedSourceIDs ?? [])")
            }
        } else {
            logger.error("Error connecting source '\(source.name)' (ID: \(source.id)): Status \(status)")
            // You might want to show an error to the user here
        }
    }

    /// Disconnects a MIDI source endpoint from the application's input port.
    /// - Parameter source: The `MIDIDeviceInfo` representing the source to disconnect.
    func disconnectSource(_ source: MIDIDeviceInfo) {
        guard inputPort != 0 else {
            logger.error("Cannot disconnect source: Input port is not initialized.")
            return
        }

        logger.info("Attempting to disconnect source: '\(source.name)' (ID: \(source.id))")
        let status = MIDIPortDisconnectSource(inputPort, source.id)

        if status == noErr {
            logger.info("Successfully disconnected source '\(source.name)'.")
            // Update the set of connected IDs on the main thread
            DispatchQueue.main.async { [weak self] in
                self?.connectedSourceIDs.remove(source.id)
                 self?.logger.debug("Updated connectedSourceIDs (removed \(source.id)). Current: \(self?.connectedSourceIDs ?? [])")
                 // Optionally clear last received note when disconnecting
                 // self?.lastReceivedNoteNumber = nil
            }
        } else {
            logger.error("Error disconnecting source '\(source.name)' (ID: \(source.id)): Status \(status)")
             // You might want to show an error to the user here
        }
    }
}

// MARK: - MIDIPacketList Sequence Conformance (macOS 11+ / iOS 14+)
// Provides a convenient way to iterate over packets using a for-in loop.
// Ensure deployment target allows this.
// REMOVED as it's redundant in modern SDKs and causes build errors.
/*
extension MIDIPacketList: Sequence {
    public typealias Element = MIDIPacketData

    public struct Iterator: IteratorProtocol {
        private let packetList: MIDIPacketList
        private var currentPacket: UnsafePointer<MIDIPacket>?

        init(packetList: MIDIPacketList) {
            self.packetList = packetList
            // Get pointer to the first packet using address-of operator (&)
            // Needs to handle the case of an empty list (numPackets = 0)
            if packetList.numPackets > 0 {
                 // Unsafe pointer to the first packet embedded in the list struct
                self.currentPacket = withUnsafePointer(to: packetList.packet) { $0 }
            } else {
                 self.currentPacket = nil // No packets to iterate
            }
        }

        public mutating func next() -> MIDIPacketData? {
            guard let current = currentPacket else { return nil }

            let packetData = MIDIPacketData(packet: current.pointee) // Extract data

            // Advance pointer to the next packet
            // MIDIPacketNext returns an UnsafePointer<MIDIPacket> which might be null
            // Use optional binding to safely advance
             let nextPacketPtr = MIDIPacketNext(current)
             // Check if the pointer returned by MIDIPacketNext is valid
             // A simple check might be if it points beyond a reasonable memory boundary,
             // or more robustly, rely on the iteration count.
             // The sequence conformance should handle the end condition gracefully.
             // A simpler approach: rely on the fact that MIDIPacketNext behavior is defined
             // for the last packet. Check documentation or test behavior.
             // Let's assume MIDIPacketNext handles the end correctly for Sequence conformance.
             // If the result of MIDIPacketNext is used within the bounds dictated by numPackets,
             // it should be safe.

             // Let's refine the logic based on typical Sequence implementation:
             // The iterator should stop *before* advancing past the last valid packet.
             // Perhaps track the index?

             // Alternative structure for Iterator:
             // Keep track of the list pointer and current index.
             // var currentIndex: UInt32 = 0
             // var pktPtr: UnsafePointer<MIDIPacket>? = &packetList.packet // Start at first
             // func next() -> MIDIPacketData? {
             //    guard currentIndex < packetList.numPackets, let current = pktPtr else { return nil }
             //    let data = MIDIPacketData(packet: current.pointee)
             //    pktPtr = MIDIPacketNext(current) // Advance for *next* call
             //    currentIndex += 1
             //    return data
             // }
             // This seems more robust. Let's implement this version.

             // --- Revised Iterator Implementation ---
             self.currentPacket = MIDIPacketNext(current) // Advance pointer for the next call

             // Check if the advanced pointer is still valid conceptually (not strictly needed if MIDIPacketNext is used correctly within loop bounds)
             // We rely on the caller (the for-in loop generated by Sequence conformance)
             // to stop after `numPackets` iterations.

            return packetData // Return the data extracted from the *current* packet
        }
    }

    public func makeIterator() -> Iterator {
        Iterator(packetList: self)
    }
}
*/

// MARK: - MIDIPacket Convenience Wrapper

/// A helper struct to more easily access data within a MIDIPacket.
public struct MIDIPacketData {
    public let timestamp: MIDITimeStamp
    public let count: Int
    public let data: [UInt8] // Swift array for easier handling

    init(packet: MIDIPacket) {
        self.timestamp = packet.timeStamp
        // Initialize count first
        let packetLength = Int(packet.length)
        self.count = packetLength

        // Access the embedded tuple `data` and convert it to a Swift array.
        // This requires accessing the unsafe raw pointer to the packet's data field.
        // The `data` field in MIDIPacket is a tuple (UInt8, UInt8, ... up to 256).
        // We need to copy the relevant number of bytes (`packet.length`).

        // Use withUnsafePointer to safely access the tuple's underlying bytes.
        let bytePtr = withUnsafePointer(to: packet.data) { ptr -> UnsafeBufferPointer<UInt8> in
            // Cast the pointer to the tuple to a raw pointer, then bind to UInt8
            let rawPtr = UnsafeRawPointer(ptr)
            // Assuming the tuple stores bytes contiguously
            // Use the local 'packetLength' instead of 'self.count' to avoid capturing 'self' before 'self.data' is initialized.
            return UnsafeBufferPointer(start: rawPtr.assumingMemoryBound(to: UInt8.self), count: packetLength)
        }
        // Now initialize self.data
        self.data = Array(bytePtr) // Create a Swift array from the buffer
    }
}
