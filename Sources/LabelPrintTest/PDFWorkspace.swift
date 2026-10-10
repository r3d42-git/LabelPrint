import AppKit
import Combine
import LabelTestCore
import UniformTypeIdentifiers

/// Owns the open document and serializes PDF rendering off the main thread.
/// Tokens prevent an older page/crop render from replacing a newer selection.
@MainActor
final class PDFWorkspace: ObservableObject {
    @Published private(set) var document: PDFLabelDocument?
    @Published private(set) var filename = ""
    @Published private(set) var pageIndex = 0
    @Published private(set) var pageImage: NSImage?
    @Published private(set) var pageSize = CGSize(width: 595, height: 842)
    @Published private(set) var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published private(set) var turns = 0
    @Published private(set) var threshold: UInt8 = 160
    @Published private(set) var raster: MonoRaster?
    @Published private(set) var labelImage: NSImage?
    @Published private(set) var isLoading = false
    @Published private(set) var isRendering = false
    @Published var error: String?
    private let queue = DispatchQueue(label: "de.r3d.labelprint.pdf", qos: .userInitiated)
    private var loadToken = UUID()
    private var renderToken = UUID()
    var pageCount: Int { document?.pageCount ?? 0 }

    func openDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "PDF öffnen"
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func load(_ url: URL) {
        let token = UUID(); loadToken = token; renderToken = UUID()
        isLoading = true; isRendering = false; raster = nil; labelImage = nil
        queue.async {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let result = Result { try PDFLabelDocument(url: url) }
            DispatchQueue.main.async {
                guard self.loadToken == token else { return }
                self.isLoading = false
                switch result {
                case .success(let document):
                    self.document = document; self.filename = url.lastPathComponent
                    self.pageIndex = 0; self.crop = CGRect(x: 0, y: 0, width: 1, height: 1)
                    self.turns = 0; self.pageImage = nil
                    self.render(includePage: true)
                case .failure(let error):
                    self.error = error.localizedDescription
                    if self.document != nil { self.render(includePage: true) }
                }
            }
        }
    }

    func selectPage(_ index: Int) {
        guard !isLoading, index >= 0, index < pageCount, index != pageIndex else { return }
        pageIndex = index; crop = CGRect(x: 0, y: 0, width: 1, height: 1); turns = 0
        pageImage = nil
        render(includePage: true)
    }
    func selectCrop(_ rect: CGRect) { crop = rect; render() }
    func wholePage() { crop = CGRect(x: 0, y: 0, width: 1, height: 1); render() }
    func rotate() { turns = (turns + 1) % 4; render() }
    func setThreshold(_ value: UInt8) { threshold = value; render() }

    private func render(includePage: Bool = false) {
        guard let document, !isLoading else { return }
        let token = UUID(); renderToken = token
        let index = pageIndex, rect = crop, rotation = turns, cutoff = threshold
        let needsPage = includePage || pageImage == nil
        isRendering = true; raster = nil; labelImage = nil
        queue.async {
            let result = Result { () -> (MonoRaster, CGImage, CGImage?, CGSize) in
                let size = try document.pageSize(at: index)
                let page = needsPage ? try document.preview(at: index) : nil
                let raster = try document.renderLabel(at: index, crop: rect, quarterTurns: rotation, threshold: cutoff)
                return (raster, try raster.cgImage(), page, size)
            }
            DispatchQueue.main.async {
                guard self.renderToken == token else { return }
                self.isRendering = false
                switch result {
                case .success(let (raster, image, page, size)):
                    self.raster = raster; self.pageSize = size
                    self.labelImage = NSImage(cgImage: image, size: NSSize(width: raster.width, height: raster.height))
                    if let page { self.pageImage = NSImage(cgImage: page, size: size) }
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
}
