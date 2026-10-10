import SwiftUI
import AppKit
import LabelTestCore
import UniformTypeIdentifiers

@main
struct LabelPrintTestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var workspace = PDFWorkspace()
    @StateObject private var printer = BluetoothPrinter()
    private var busy: Bool { printer.isSending || printer.isConnecting || printer.isPrinterBusy }

    var body: some Scene {
        Window("LabelPrint · D520BT", id: "main") {
            LabelPrintView(workspace: workspace, printer: printer)
                .frame(minWidth: 1040, minHeight: 720)
        }
        .defaultSize(width: 1240, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("PDF öffnen …") { workspace.openDialog() }
                    .keyboardShortcut("o").disabled(busy || workspace.isLoading)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

private struct PreparedPrint {
    let data: Data
    let title: String
}

struct LabelPrintView: View {
    @ObservedObject var workspace: PDFWorkspace
    @ObservedObject var printer: BluetoothPrinter
    @State private var selection: String?
    @State private var settings = PrintSettings()
    @State private var details = false
    @State private var includeClassic = false
    @State private var zoom: Double = 1
    @State private var pendingJob: PreparedPrint?
    @State private var lastJob = "Noch kein Druckauftrag gesendet."
    @AppStorage("lastPrinterID") private var lastPrinterID = ""

    private var busy: Bool { printer.isSending || printer.isConnecting || printer.isPrinterBusy || pendingJob != nil }
    private var device: PrinterDevice? { printer.devices.first { $0.id == selection } }
    private var canSend: Bool { !busy && !printer.isScanning && (printer.isConnected || device != nil) }
    private var canPrintPDF: Bool { canSend && workspace.raster != nil && !workspace.isLoading && !workspace.isRendering }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            pdfEditor.frame(minWidth: 470, maxWidth: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    labelPreview
                    printerControls
                    diagnostics
                }.padding(20)
            }.frame(width: 385)
        }
        .onOpenURL { url in
            if busy { workspace.error = "Bitte den laufenden Druckauftrag abwarten, bevor du ein anderes PDF öffnest." }
            else { workspace.load(url); zoom = 1 }
        }
        .onChange(of: selection) { _, id in if let id { lastPrinterID = id } }
        .onChange(of: printer.devices) { _, devices in
            if devices.contains(where: { $0.id == lastPrinterID }) { selection = lastPrinterID }
            else if let selection, !devices.contains(where: { $0.id == selection }) { self.selection = nil }
        }
        .onChange(of: printer.isScanning) { _, scanning in
            if !scanning && selection == nil && printer.devices.count == 1 { selection = printer.devices[0].id }
        }
        .onChange(of: printer.isConnected) { _, connected in
            if connected, let job = pendingJob {
                pendingJob = nil
                transmit(job)
            }
        }
        .onChange(of: printer.isConnecting) { _, connecting in
            if !connecting && !printer.isConnected { pendingJob = nil }
        }
        .alert("LabelPrint", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
            Button("OK") { workspace.error = nil }
        } message: { Text(workspace.error ?? "") }
    }

    private var pdfEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LabelPrint").font(.largeTitle.bold())
                Spacer()
                Button("PDF öffnen …", systemImage: "doc.badge.plus") { workspace.openDialog(); zoom = 1 }
                    .disabled(busy || workspace.isLoading)
            }
            if workspace.document != nil {
                Text(workspace.filename).font(.headline).lineLimit(1).truncationMode(.middle).help(workspace.filename)
                HStack {
                    Button { workspace.selectPage(workspace.pageIndex - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(workspace.pageIndex == 0 || busy || workspace.isLoading)
                        .help("Vorherige Seite")
                        .accessibilityLabel("Vorherige Seite")
                    Text("Seite \(workspace.pageIndex + 1) von \(workspace.pageCount)").monospacedDigit()
                    Button { workspace.selectPage(workspace.pageIndex + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(workspace.pageIndex + 1 >= workspace.pageCount || busy || workspace.isLoading)
                        .help("Nächste Seite")
                        .accessibilityLabel("Nächste Seite")
                    Spacer()
                    Picker("Ansicht", selection: $zoom) {
                        Text("Einpassen").tag(1.0)
                        Text("150 %").tag(1.5)
                        Text("200 %").tag(2.0)
                        Text("300 %").tag(3.0)
                    }.frame(width: 170)
                }
                HStack {
                    Label("Druckbereich mit der Maus aufziehen", systemImage: "crop")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Ganze Seite") { workspace.wholePage() }.disabled(busy || workspace.isLoading)
                }
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        if let image = workspace.pageImage {
                            PDFCropCanvas(image: image, selection: workspace.crop, enabled: !busy && !workspace.isLoading,
                                          onSelect: { workspace.selectCrop($0) })
                                .frame(width: max(100, geometry.size.width * zoom), height: max(100, geometry.size.height * zoom))
                        } else {
                            VStack { Spacer(); ProgressView("PDF-Seite wird geladen …"); Spacer() }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                }
                .background(.quaternary.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("Das Original bleibt unverändert. Auswahl wird proportional auf 103 × 199 mm eingepasst.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "doc.viewfinder").font(.system(size: 54)).foregroundStyle(.secondary)
                    Text("PDF öffnen und Etikett markieren").font(.title2)
                    Text("1. PDF öffnen   2. Bereich aufziehen   3. Drucken")
                        .foregroundStyle(.secondary)
                    if workspace.isLoading { ProgressView("PDF wird geladen …") }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(22)
    }

    private var labelPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Druckvorschau").font(.headline)
                Spacer()
                Button { workspace.rotate() } label: { Image(systemName: "rotate.right") }
                    .help("Ausschnitt um 90° im Uhrzeigersinn drehen")
                    .accessibilityLabel("Ausschnitt um 90 Grad drehen")
                    .disabled(workspace.document == nil || busy || workspace.isLoading)
            }
            ZStack {
                Rectangle().fill(.white)
                if let image = workspace.labelImage {
                    Image(nsImage: image).interpolation(.high).resizable().scaledToFit()
                } else if workspace.isRendering || workspace.isLoading {
                    ProgressView().tint(.gray)
                } else {
                    Text("Noch kein PDF geladen").foregroundStyle(.gray).font(.callout)
                }
            }
            .aspectRatio(103.0 / 199.0, contentMode: .fit)
            .frame(maxHeight: 365)
            .overlay(Rectangle().stroke(.gray.opacity(0.4), lineWidth: 1))
            .frame(maxWidth: .infinity)
            Text("103 × 199 mm · 3 mm Rand · \(workspace.turns * 90)°")
                .font(.caption).foregroundStyle(.secondary)
            Button("Etikett drucken", systemImage: "printer") { printPDF() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!canPrintPDF)
            Text(lastJob).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private var printerControls: some View {
        GroupBox("D520BT · Bluetooth") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button(printer.isScanning ? "Suche stoppen" : "Drucker suchen") {
                        if printer.isScanning { printer.stopScan() }
                        else { printer.scan(includeClassic: includeClassic) }
                    }.disabled(busy || printer.isConnected)
                    if printer.isScanning { ProgressView().controlSize(.small) }
                    Spacer()
                }
                Picker("Drucker", selection: $selection) {
                    Text("Bitte auswählen").tag(nil as String?)
                    ForEach(printer.devices) { item in
                        Text("\(item.name) · \(item.transport)").tag(Optional(item.id))
                    }
                }.disabled(busy || printer.isConnected)
                HStack {
                    Button("Verbinden") { if let device { printer.connect(device) } }
                        .disabled(device == nil || busy || printer.isScanning || printer.isConnected)
                    Button(printer.isSending ? "Übertragung abbrechen" : "Trennen") {
                        pendingJob = nil; printer.disconnect()
                    }.disabled(!printer.isConnected && !busy)
                }
                Text(printer.status).font(.caption).textSelection(.enabled)
                Text(printer.printerStatus).font(.caption).foregroundStyle(.secondary)
                if printer.isSending { ProgressView(value: printer.progress) }
            }.padding(6)
        }
    }

    private var diagnostics: some View {
        DisclosureGroup("Druckeinstellungen und Diagnose", isExpanded: $details) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Dichte", selection: $settings.density) {
                        ForEach(0...15, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Tempo", selection: $settings.speed) {
                        ForEach(2...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                }.disabled(busy)
                Stepper("Etikettenlücke: \(settings.gapMM) mm", value: $settings.gapMM, in: 0...9).disabled(busy)
                Picker("PDF-Grautöne", selection: Binding(get: { workspace.threshold }, set: { workspace.setThreshold($0) })) {
                    Text("Heller").tag(UInt8(120))
                    Text("Normal").tag(UInt8(160))
                    Text("Kräftiger").tag(UInt8(200))
                }.disabled(busy || workspace.isLoading)
                Text("Die Druckvorschau zeigt die tatsächlich gesendeten Schwarzweiß-Punkte. Vorhandene weiße Freiräume um Codes beim Zuschneiden erhalten.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Druckvorschau speichern …", action: savePreview).disabled(workspace.raster == nil)
                Divider()
                Button("Verbindungsetikett drucken") { printTest(quality: false) }.disabled(!canSend)
                Button("QR-/Barcode-Test drucken") { printTest(quality: true) }.disabled(!canSend)
                Toggle("Classic zusätzlich suchen (experimentell)", isOn: $includeClassic)
                    .disabled(busy || printer.isScanning || printer.isConnected)
                Button("Protokoll kopieren") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(printer.log, forType: .string)
                }
                ScrollView {
                    Text(printer.log.isEmpty ? "Noch keine Bluetooth-Aktivität." : printer.log)
                        .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 120)
            }.padding(.top, 10)
        }
    }

    private func printPDF() {
        guard canPrintPDF, let raster = workspace.raster else { return }
        do {
            // Freeze the exact preview and settings before any asynchronous connection attempt.
            let data = try TestLabel.rasterJob(raster, settings: settings)
            submit(PreparedPrint(data: data, title: "\(workspace.filename) · Seite \(workspace.pageIndex + 1)"))
        } catch { workspace.error = error.localizedDescription }
    }
    private func printTest(quality: Bool) {
        guard canSend else { return }
        do {
            let data = try quality ? TestLabel.rasterJob(TestLabel.render(settings: settings), settings: settings)
                                   : TestLabel.connectionJob(settings: settings)
            submit(PreparedPrint(data: data, title: quality ? "QR-/Barcode-Test" : "Verbindungstest"))
        } catch { workspace.error = error.localizedDescription }
    }
    private func submit(_ job: PreparedPrint) {
        if printer.isConnected { transmit(job) }
        else if let device {
            pendingJob = job
            printer.connect(device)
            // A connection can be rejected immediately while an earlier BLE disconnect finishes.
            if !printer.isConnecting && !printer.isConnected { pendingJob = nil }
        }
    }
    private func transmit(_ job: PreparedPrint) {
        lastJob = "\(job.title) · 1 Etikett · \(job.data.count) Bytes"
        printer.send(job.data)
    }
    private func savePreview() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "LabelPrint-103x199.png"
        if panel.runModal() == .OK, let url = panel.url {
            do { try workspace.raster?.writePNG(to: url) }
            catch { workspace.error = error.localizedDescription }
        }
    }
}
