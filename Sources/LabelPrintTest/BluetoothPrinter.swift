import Foundation
import Combine
import IOBluetooth
import CoreBluetooth
import LabelTestCore

struct PrinterDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let transport: String
}

/// The transport reports delivery to the Bluetooth stack, never physical print success.
final class BluetoothPrinter: NSObject, ObservableObject, IOBluetoothDeviceInquiryDelegate,
    IOBluetoothRFCOMMChannelDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var devices: [PrinterDevice] = []
    @Published var selectedID: String?
    @Published var status = "Bereit. Bluetooth-Suche startet erst auf Anforderung."
    @Published var isScanning = false
    @Published var isConnecting = false
    @Published var isConnected = false
    @Published var isSending = false
    @Published var progress: Double = 0
    @Published var log = ""
    @Published var printerStatus = "Noch keine Druckerrückmeldung."
    @Published var isPrinterBusy = false
    var connectedName: String { activeName }

    private var classicDevices: [String: IOBluetoothDevice] = [:]
    private var peripherals: [String: CBPeripheral] = [:]
    private var inquiry: IOBluetoothDeviceInquiry?
    private var central: CBCentralManager?
    private var scanTimer: DispatchWorkItem?
    private var connectionTimer: DispatchWorkItem?
    private var transferTimer: DispatchWorkItem?
    private var session = UUID()
    private var activeName = ""
    private var channel: IOBluetoothRFCOMMChannel?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var sdpTarget: SDPCompletion?
    // IOBluetooth delegates are not retained by the framework. Keep outstanding SDP targets alive.
    private var retiredSDPTargets: [SDPCompletion] = []
    private var pendingBLEConnection: UUID?
    private var closingPeripherals: Set<UUID> = []
    private var bleWritePending = 0
    private var job = Data()
    private var offset = 0
    private var rxTail = Data()
    // Buffers must outlive writeAsync, even if cancellation closes the channel first.
    private var buffers: [UInt: NSMutableData] = [:]
    private var lines: [String] = []
    private var replyParser = PrinterReplyParser()
    private var transferStarted: UInt64 = 0
    private var packetsSent = 0

    private func append(_ message: String) {
        lines.append(message)
        if lines.count > 300 { lines.removeFirst(lines.count - 300) }
        log = lines.joined(separator: "\n")
    }
    private func candidate(_ name: String) -> Bool {
        let value = name.uppercased()
        return value.contains("D520") || value.contains("PHOMEMO") || value.hasPrefix("QR")
    }
    private func add(_ item: PrinterDevice) {
        if let index = devices.firstIndex(where: { $0.id == item.id }) { devices[index] = item }
        else { devices.append(item) }
        devices.sort {
            if $0.id.hasPrefix("ble:") != $1.id.hasPrefix("ble:") { return $0.id.hasPrefix("ble:") }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread { action() } else { DispatchQueue.main.async(execute: action) }
    }

    func scan(includeClassic: Bool = false) {
        guard !isConnecting, !isConnected, !isSending else { return }
        stopScan()
        devices.removeAll(); classicDevices.removeAll(); peripherals.removeAll()
        isScanning = true; status = "Suche nach D520 / Phomemo / QR …"
        append(includeClassic ? "Suche: BLE und experimentelles Classic SPP." : "Suche: BLE (am D520 erfolgreich getestet).")
        if includeClassic {
            for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []) { foundClassic(device) }
            let search = IOBluetoothDeviceInquiry(delegate: self)
            inquiry = search
            search?.inquiryLength = 10
            search?.updateNewDeviceNames = true
            let result = search?.start() ?? kIOReturnError
            if result != kIOReturnSuccess { append("Classic-Suche konnte nicht starten: \(result)") }
        }
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { startBLEScanIfReady() }
        let timeout = DispatchWorkItem { [weak self] in self?.stopScan() }
        scanTimer = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
    }
    func stopScan() {
        scanTimer?.cancel(); scanTimer = nil
        let search = inquiry; inquiry = nil
        search?.delegate = nil; _ = search?.stop()
        central?.stopScan()
        if isScanning { status = devices.isEmpty ? "Keine passenden Drucker gefunden." : "Suche beendet. Drucker auswählen." }
        isScanning = false
    }
    private func startBLEScanIfReady() {
        guard isScanning, central?.state == .poweredOn else { return }
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    private func foundClassic(_ device: IOBluetoothDevice) {
        let name = device.name ?? ""
        guard candidate(name), let address = device.addressString else { return }
        let id = "classic:\(address)"
        let isNew = classicDevices[id] == nil
        classicDevices[id] = device
        add(PrinterDevice(id: id, name: name, transport: "Classic · SPP"))
        if isNew { append("Classic gefunden: \(name) [\(address)]") }
    }
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        onMain { [weak self] in guard let self, sender === self.inquiry, let device else { return }; self.foundClassic(device) }
    }
    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        deviceInquiryDeviceFound(sender, device: device)
    }
    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        onMain { [weak self] in guard let self, sender === self.inquiry else { return }; self.append("Classic-Suche beendet: \(error). BLE-Suche läuft bis zum Zeitlimit.") }
    }

    func connect(_ device: PrinterDevice) {
        guard !isSending, !isConnecting else { return }
        if let ble = peripherals[device.id], closingPeripherals.contains(ble.identifier) {
            status = "BLE-Trennung läuft noch. Bitte kurz warten und erneut verbinden."
            return
        }
        disconnect(); stopScan()
        if let ble = peripherals[device.id], closingPeripherals.contains(ble.identifier) {
            status = "BLE-Trennung läuft noch. Bitte kurz warten und erneut verbinden."
            return
        }
        selectedID = device.id; activeName = device.name
        session = UUID(); let token = session
        replyParser = PrinterReplyParser()
        printerStatus = "Noch keine Druckerrückmeldung."
        isPrinterBusy = false
        isConnecting = true; status = "Verbinde mit \(device.name) …"; rxTail.removeAll()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.session == token, self.isConnecting else { return }
            self.fail("Verbindungsaufbau hat das Zeitlimit überschritten.")
        }
        connectionTimer = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
        if let classic = classicDevices[device.id] {
            let target = SDPCompletion { [weak self] actual, result in
                self?.onMain { [weak self] in
                    guard let self, self.session == token, self.isConnecting else { return }
                    guard result == kIOReturnSuccess else { self.fail("SDP fehlgeschlagen: \(result)"); return }
                    self.openSPP(actual)
                }
            }
            sdpTarget = target; retiredSDPTargets.append(target)
            let result = classic.performSDPQuery(target)
            if result != kIOReturnSuccess { fail("SDP konnte nicht starten: \(result)") }
        } else if let ble = peripherals[device.id], central?.state == .poweredOn {
            peripheral = ble; ble.delegate = self; pendingBLEConnection = token
            central?.connect(ble, options: nil)
        } else { fail("Gerät nicht mehr verfügbar. Bitte erneut suchen.") }
    }
    private func openSPP(_ device: IOBluetoothDevice) {
        let uuid = IOBluetoothSDPUUID(uuid16: 0x1101)
        guard let record = device.getServiceRecord(for: uuid) else { fail("Kein SPP-Dienst (1101). Keine Daten gesendet."); return }
        var number: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&number) == kIOReturnSuccess, number > 0 else { fail("SPP enthält keinen gültigen RFCOMM-Kanal."); return }
        append("SDP: SPP 1101, RFCOMM-Kanal \(number).")
        var opened: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&opened, withChannelID: number, delegate: self)
        channel = opened
        if result != kIOReturnSuccess { fail("RFCOMM konnte nicht öffnen: \(result)") }
    }
    private func ready() {
        connectionTimer?.cancel(); connectionTimer = nil
        isConnected = true; isConnecting = false
        status = "Verbunden mit \(activeName). Bereit zum manuellen Senden."
        append("Verbindung bereit. Keine automatischen Status- oder Druckkommandos.")
    }
    func disconnect() {
        let uncertain = isSending
        session = UUID(); pendingBLEConnection = nil
        connectionTimer?.cancel(); transferTimer?.cancel()
        connectionTimer = nil; transferTimer = nil
        let old = channel; channel = nil; _ = old?.close()
        if let ble = peripheral {
            if ble.state != .disconnected { closingPeripherals.insert(ble.identifier) }
            ble.delegate = nil; central?.cancelPeripheralConnection(ble)
        }
        peripheral = nil; characteristic = nil; sdpTarget = nil
        isConnecting = false; isConnected = false; isSending = false
        isPrinterBusy = false
        job.removeAll(); offset = 0; bleWritePending = 0
        status = uncertain ? "Abgebrochen: Teilauftrag ungewiss. Ausdruck prüfen und Drucker vor erneutem Versuch aus-/einschalten." : "Verbindung getrennt."
        if uncertain { append(status) }
    }
    private func fail(_ reason: String) {
        let uncertain = isSending
        disconnect()
        status = reason + (uncertain ? " Teilauftrag ungewiss; Ausdruck prüfen und Drucker vor erneutem Versuch aus-/einschalten. Kein automatischer Wiederholungsversuch." : " Verbindung geschlossen.")
        append(status)
    }
    func send(_ data: Data) {
        guard isConnected, !isSending, !isPrinterBusy, !data.isEmpty else { return }
        job = data; offset = 0; progress = 0; isSending = true; bleWritePending = 0
        transferStarted = DispatchTime.now().uptimeNanoseconds; packetsSent = 0
        printerStatus = "Warte auf Druckerrückmeldung."
        if let peripheral, let characteristic {
            let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
            append("BLE: \(type == .withResponse ? "mit Bestätigung" : "ohne Bestätigung"), Paketlimit \(peripheral.maximumWriteValueLength(for: type)) Bytes.")
        }
        status = "Übertrage \(data.count) Bytes …"; append(status)
        armTransferTimeout(); writeNext()
    }
    private func armTransferTimeout() {
        transferTimer?.cancel()
        let token = session
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.session == token, self.isSending else { return }
            self.fail("Übertragung ohne Fortschritt (15 Sekunden).")
        }
        transferTimer = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
    }
    private func accepted(_ count: Int) {
        guard isSending else { return }
        offset += count; progress = Double(offset) / Double(job.count)
        packetsSent += 1
        armTransferTimeout()
        if offset >= job.count {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - transferStarted) / 1_000_000_000
            let totalBytes = job.count
            transferTimer?.cancel(); transferTimer = nil; isSending = false; job.removeAll()
            status = String(format: "Daten in %.1f s übertragen; Ausdruck prüfen.", elapsed)
            append(status)
            append(String(format: "%d Bytes / %d Pakete / %.0f Bytes pro Sekunde.", totalBytes, packetsSent, Double(totalBytes) / max(elapsed, 0.001)))
        }
    }
    private func writeNext() {
        guard isSending, offset < job.count else { return }
        if let channel {
            let count = min(Int(channel.getMTU()), job.count - offset, Int(UInt16.max))
            guard count > 0 else { fail("Ungültige RFCOMM-MTU."); return }
            let buffer = NSMutableData(data: job.subdata(in: offset..<(offset + count)))
            let pointer = buffer.mutableBytes
            buffers[UInt(bitPattern: pointer)] = buffer
            let result = channel.writeAsync(pointer, length: UInt16(count), refcon: pointer)
            if result != kIOReturnSuccess {
                buffers.removeValue(forKey: UInt(bitPattern: pointer)); fail("RFCOMM-Schreibfehler: \(result)")
            }
        } else if let peripheral, let characteristic {
            guard bleWritePending == 0 else { return }
            let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
            if type == .withoutResponse && !peripheral.canSendWriteWithoutResponse { return }
            let count = min(peripheral.maximumWriteValueLength(for: type), job.count - offset)
            guard count > 0 else { fail("Ungültige BLE-Paketgröße."); return }
            let chunk = job.subdata(in: offset..<(offset + count))
            bleWritePending = count
            peripheral.writeValue(chunk, for: characteristic, type: type)
            if type == .withoutResponse {
                let token = session
                // Stack acceptance is not a peripheral acknowledgement; conservative pacing avoids a busy loop.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                    guard let self, self.session == token, self.isSending else { return }
                    self.bleWritePending = 0; self.accepted(count); self.writeNext()
                }
            }
        } else { fail("Kein validierter Datenkanal.") }
    }
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        onMain { [weak self] in
            guard let self, rfcommChannel === self.channel, self.isConnecting else { _ = rfcommChannel?.close(); return }
            if error == kIOReturnSuccess { self.ready() } else { self.fail("RFCOMM-Verbindungsfehler: \(error)") }
        }
    }
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        onMain { [weak self] in guard let self, rfcommChannel === self.channel else { return }; self.fail("RFCOMM-Verbindung beendet.") }
    }
    func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        onMain { [weak self] in
            guard let self, let refcon, let buffer = self.buffers.removeValue(forKey: UInt(bitPattern: refcon)) else { return }
            guard rfcommChannel === self.channel, self.isSending else { return }
            if error == kIOReturnSuccess { self.accepted(buffer.length); self.writeNext() }
            else { self.fail("RFCOMM-Übertragung fehlgeschlagen: \(error)") }
        }
    }
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard let dataPointer, dataLength > 0 else { return }
        let bytes = Data(bytes: dataPointer, count: min(dataLength, 256))
        onMain { [weak self] in guard let self, rfcommChannel === self.channel else { return }; self.received(bytes) }
    }
    private func received(_ bytes: Data) {
        append("RX: " + bytes.prefix(48).map { String(format: "%02X", $0) }.joined(separator: " ") + (bytes.count > 48 ? " …" : ""))
        let combined = rxTail + bytes
        if combined.range(of: Data([0x7E, 0x00, 0x7E])) != nil {
            fail("Drucker meldet Ablehnung (7E 00 7E). Vor einem neuen Versuch Ausdruck prüfen und Drucker aus-/einschalten.")
            rxTail.removeAll()
            return
        }
        if combined.range(of: Data([0x7E, 0x01, 0x7E])) != nil { append("Empfangen: 7E 01 7E (Auftrags-ACK, informativ; Ausdruck prüfen).") }
        rxTail = Data(combined.suffix(2))
        for state in replyParser.consume(bytes) {
            switch state {
            case .printing:
                isPrinterBusy = true
                printerStatus = "Drucker meldet: Druck läuft."
            case .done:
                isPrinterBusy = false
                printerStatus = "Drucker meldet: Druck fertig. Ausdruck und Codes prüfen."
            }
            append(printerStatus)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: startBLEScanIfReady()
        case .unknown, .resetting: break
        default:
            append("BLE-Zustand: \(central.state.rawValue) (Berechtigung / Bluetooth prüfen).")
            if peripheral != nil { fail("BLE ist nicht verfügbar.") }
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard isScanning else { return }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        guard candidate(name) else { return }
        let id = "ble:\(peripheral.identifier.uuidString)"
        let isNew = peripherals[id] == nil
        peripherals[id] = peripheral
        add(PrinterDevice(id: id, name: name, transport: "BLE"))
        if isNew { append("BLE gefunden: \(name)") }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral, isConnecting, pendingBLEConnection == session else { central.cancelPeripheralConnection(peripheral); return }
        peripheral.discoverServices(nil)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        closingPeripherals.remove(peripheral.identifier)
        guard peripheral === self.peripheral else { return }; fail("BLE-Verbindungsfehler: \(error?.localizedDescription ?? "unbekannt")")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        closingPeripherals.remove(peripheral.identifier)
        guard peripheral === self.peripheral else { return }; fail("BLE-Verbindung beendet: \(error?.localizedDescription ?? "getrennt")")
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral, isConnecting else { return }
        guard error == nil else { fail("BLE-Dienstsuche: \(error!.localizedDescription)"); return }
        let services = peripheral.services ?? []
        append("BLE-Dienste: " + services.map { $0.uuid.uuidString }.joined(separator: ", "))
        guard let service = services.first(where: { $0.uuid == CBUUID(string: "FF00") }) else { fail("BLE: kein FF00-Dienst. Unbekannte Dienste werden nicht beschrieben."); return }
        peripheral.discoverCharacteristics(nil, for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral, isConnecting, service.uuid == CBUUID(string: "FF00") else { return }
        guard error == nil else { fail("BLE-Characteristic-Suche: \(error!.localizedDescription)"); return }
        let list = service.characteristics ?? []
        append("FF00-Characteristics: " + list.map { "\($0.uuid.uuidString) Eigenschaften=\($0.properties.rawValue)" }.joined(separator: ", "))
        guard let output = list.first(where: { $0.uuid == CBUUID(string: "FF02") && ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)) }) else { fail("BLE: FF02 ist nicht schreibbar. Keine Daten gesendet."); return }
        characteristic = output
        if let input = list.first(where: { $0.uuid == CBUUID(string: "FF01") && ($0.properties.contains(.notify) || $0.properties.contains(.indicate)) }) {
            peripheral.setNotifyValue(true, for: input)
        }
        append("BLE FF00/FF02 validiert; Übertragung meldet nur Stack-Zustellung.")
        ready()
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic === self.characteristic, isSending, bleWritePending > 0 else { return }
        if let error { fail("BLE-Schreibfehler: \(error.localizedDescription)"); return }
        let count = bleWritePending; bleWritePending = 0; accepted(count); writeNext()
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }; writeNext()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, characteristic.uuid == CBUUID(string: "FF01"), characteristic.service?.uuid == CBUUID(string: "FF00") else { return }
        if let error { append("BLE RX-Fehler: \(error.localizedDescription)") }
        else if let value = characteristic.value { received(Data(value.prefix(256))) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral else { return }
        append("BLE Notifications \(characteristic.uuid): \(error?.localizedDescription ?? (characteristic.isNotifying ? "aktiv" : "inaktiv"))")
    }
}

private final class SDPCompletion: NSObject {
    let completion: (IOBluetoothDevice, IOReturn) -> Void
    init(_ completion: @escaping (IOBluetoothDevice, IOReturn) -> Void) { self.completion = completion }
    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        if let device { completion(device, status) }
    }
}
