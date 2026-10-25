import Foundation

/// An entry on the Tools wheel. Which tools appear depends on the dragged files.
enum FileTool: CaseIterable, Hashable {
    // Images. `WheelOrdering` sets their order on the wheel.
    case compress
    case metadata
    case edit
    case annotate
    case addBackground
    case crop
    case resize
    case removeBackground
    case redact
    case readQR
    // PDFs (and images, for Combine).
    case combinePDF
    case organizePages
    case splitPDF
    case compressPDF
    case pdfMetadata
    case makeFillable
    // Video and audio.
    case trim
    case speed
    case cropVideo
    case compressVideo
    case mute
    case mergeMedia
    case splitMedia
    case rotateVideo
    case stillFrame
    case reverse
    case mediaMetadata
    case mono
    case normalize
    case grayscale
    case volume
    case ocr
    case transcribe
    case fitSize
    case compressAudio
    case pdfImages
    case frameRate
    case gifLoop
    case icon
    case export
    case sqliteTables
    // Source code.
    case prettyPrint

    var title: String {
        switch self {
        case .compress: "Compress"
        case .metadata: "Metadata"
        case .edit: "Edit"
        case .annotate: "Annotate"
        case .addBackground: "Add BG"
        case .crop: "Crop"
        case .resize: "Resize"
        case .removeBackground: "Remove BG"
        case .redact: "Redact"
        case .readQR: "Read QR"
        case .combinePDF: "Combine"
        case .organizePages: "Pages"
        case .splitPDF: "Split"
        case .compressPDF: "Compress"
        case .pdfMetadata: "Metadata"
        case .makeFillable: "Make Fillable"
        case .trim: "Trim"
        case .speed: "Speed"
        case .cropVideo: "Crop"
        case .compressVideo: "Compress"
        case .mute: "Mute"
        case .mergeMedia: "Merge"
        case .splitMedia: "Split"
        case .rotateVideo: "Rotate"
        case .stillFrame: "Still"
        case .reverse: "Reverse"
        case .mediaMetadata: "Metadata"
        case .mono: "Mono"
        case .normalize: "Loudness"
        case .grayscale: "Grayscale"
        case .volume: "Volume"
        case .ocr: "OCR"
        case .transcribe: "Transcribe"
        case .fitSize: "Fit Size"
        case .compressAudio: "Compress"
        case .pdfImages: "Images"
        case .frameRate: "Frame Rate"
        case .gifLoop: "Loop"
        case .icon: "Icon"
        case .export: "Export"
        case .sqliteTables: "Tables"
        case .prettyPrint: "Pretty Print"
        }
    }

    var systemImage: String {
        switch self {
        case .compress, .compressPDF, .compressVideo, .compressAudio: "arrow.down.right.and.arrow.up.left"
        case .metadata, .pdfMetadata, .mediaMetadata: "tag"
        case .edit: "slider.horizontal.3"
        case .annotate: "pencil.tip.crop.circle"
        case .addBackground: "photo.on.rectangle"
        case .crop, .cropVideo: "crop"
        case .resize: "arrow.up.left.and.arrow.down.right"
        case .removeBackground: "person.crop.rectangle"
        case .redact: "eye.slash"
        case .readQR: "qrcode.viewfinder"
        case .combinePDF: "doc.on.doc"
        case .organizePages: "square.grid.2x2"
        case .splitPDF: "scissors"
        case .makeFillable: "rectangle.and.pencil.and.ellipsis"
        case .trim: "timeline.selection"
        case .speed: "gauge.with.dots.needle.67percent"
        case .mute: "speaker.slash"
        case .mergeMedia: "arrow.triangle.merge"
        case .splitMedia: "scissors"
        case .rotateVideo: "rotate.right"
        case .stillFrame: "photo"
        case .reverse: "backward"
        case .mono: "speaker.wave.1"
        case .normalize: "waveform"
        case .grayscale: "circle.lefthalf.filled"
        case .volume: "speaker.wave.3"
        case .ocr: "text.viewfinder"
        case .pdfImages: "photo.on.rectangle.angled"
        case .frameRate: "film.stack"
        case .gifLoop: "repeat"
        case .icon: "app.dashed"
        case .export: "square.and.arrow.up.on.square"
        case .sqliteTables: "tablecells"
        case .prettyPrint: "text.alignleft"
        case .transcribe: "captions.bubble"
        case .fitSize: "externaldrive.badge.checkmark"
        }
    }

    /// Containers Apple's media framework can edit. Others (MKV, WebM, AVI, WMV,
    /// FLV, MKA, WMA, …) only convert, through ffmpeg; AVI is listed by
    /// AVFoundation but its common codecs don't open, so it's left out too.
    static let editableMediaExtensions: Set<String> = [
        "mp4", "mov", "m4v", "3gp", "m4a", "mp3", "wav", "aif", "aiff", "caf", "aac", "flac", "ogg", "opus",
    ]

    /// Whether the media tools can edit `url`: what Apple's media framework
    /// edits, and with ffmpeg also MKV, WebM and AVI (see `KeepFormat`).
    static func isEditable(_ url: URL, tools: ExternalTools = .current) -> Bool {
        editableMediaExtensions.contains(url.resolvingSymlinksInPath().pathExtension.lowercased())
            || (tools.ffmpeg != nil && KeepFormat.isFFmpegContainer(url))
    }

    /// Whether every file is audio or video the media tools can't open.
    static func needsConversionForTools(_ urls: [URL], tools: ExternalTools = .current) -> Bool {
        !urls.isEmpty && urls.allSatisfy { url in
            let kind = FileKind(url: url)
            return (kind == .video || kind == .audio) && !isEditable(url, tools: tools)
        }
    }

    /// What to tell someone who opened the Tools wheel on such files, mid-drag.
    /// Short enough for the toast's single-line title and subtitle. Converting
    /// MKV, WebM, WMA and friends takes ffmpeg; without it, say that instead.
    /// - Parameter convertKeys: The Convert wheel's trigger, e.g. "⇧".
    static func convertFirstToast(for urls: [URL], convertKeys: String, tools: ExternalTools) -> Toast {
        let unreadable = urls.filter { !MediaFormats.isAVFoundationReadable($0) }
        if tools.ffmpeg == nil, !unreadable.isEmpty {
            return MissingToolAdvice.toast(for: unreadable, needing: .extra(.ffmpeg), tools: tools)
        }
        let kinds = Set(urls.map { FileKind(url: $0) })
        var format = "MP4 or M4A"
        if kinds == [.video] {
            format = "MP4"
        } else if kinds == [.audio] {
            format = "M4A"
        }
        return Toast(
            systemImage: "arrow.triangle.2.circlepath",
            title: "Convert to \(format) first",
            subtitle: "Tap \(convertKeys) while dragging to convert"
        )
    }

    /// Tools that apply to every file in `urls`; `WheelOrdering` orders long lists for the wheel.
    static func available(for urls: [URL], tools: ExternalTools = .current) -> [FileTool] {
        guard !urls.isEmpty else { return [] }
        let kinds = Set(urls.map { FileKind(url: $0) })
        let combine: [FileTool] = urls.count > 1 && kinds.isSubset(of: [.image, .pdf]) ? [.combinePDF] : []

        if kinds == [.image] {
            let gifs: [FileTool] = urls.allSatisfy { $0.pathExtension.lowercased() == "gif" } ? [.gifLoop] : []
            return [.compress, .metadata, .edit, .annotate, .addBackground, .crop, .resize, .removeBackground, .redact, .readQR, .ocr, .icon] + gifs + combine
        }
        if urls.allSatisfy({ PrettyPrint.formatter(for: $0, tools: tools) != nil }) {
            return [.prettyPrint]
        }
        if urls.count == 1, kinds == [.data], DatabaseConversion.isSQLite(urls[0]) {
            return [.sqliteTables]
        }
        if kinds == [.pdf] {
            // PDF Images and Make Fillable work on one file; the other page tools take several.
            let images: [FileTool] = urls.count == 1 ? [.pdfImages] : []
            let fillable: [FileTool] = urls.count == 1 && tools.commonforms != nil ? [.makeFillable] : []
            return combine + [.organizePages, .splitPDF] + images + [.compressPDF, .pdfMetadata, .ocr] + fillable
        }
        if kinds.isSubset(of: [.video, .audio]), !urls.allSatisfy({ isEditable($0, tools: tools) }) {
            return []
        }
        let merge: [FileTool] = urls.count > 1 ? [.mergeMedia] : []
        // Tools only ffmpeg does.
        let hasFFmpeg = tools.ffmpeg != nil
        if kinds == [.video] {
            return merge + [.trim, .speed, .cropVideo, .rotateVideo, .splitMedia, .compressVideo, .mute, .stillFrame, .grayscale, .transcribe]
                + (hasFFmpeg ? [.reverse, .mediaMetadata, .normalize, .volume, .fitSize, .frameRate, .export] : [])
        }
        if kinds == [.audio] {
            return merge + [.trim, .speed, .splitMedia, .compressAudio, .export, .transcribe] + (hasFFmpeg ? [.reverse, .mediaMetadata, .mono, .normalize, .volume, .fitSize] : [])
        }
        return kinds.isSubset(of: [.image, .pdf]) ? combine + [.ocr] : combine
    }
}
