import AppKit

/// Runs a Tools-wheel entry: opens its editor, or runs it straight away for
/// one-click tools (Combine, Mute, Read QR).
@MainActor
enum ToolLauncher {
    /// - Parameter sourceShelfID: The shelf `urls` were dragged or selected
    ///   from, if any; carried through so the tool's output can be added
    ///   back to it.
    static func open(_ tool: FileTool, with urls: [URL], near location: NSPoint = NSEvent.mouseLocation, sourceShelfID: Shelf.ID? = nil) {
        guard let first = urls.first else { return }
        let runner = ConversionRunner.shared

        switch tool {
        case .compress, .metadata, .edit, .annotate, .addBackground, .crop, .resize, .removeBackground, .redact:
            openImageEditor(tool, with: urls, near: location, sourceShelfID: sourceShelfID)

        case .readQR:
            Task {
                do {
                    let codes = try await QRReader.read(urls)
                    guard !codes.isEmpty else {
                        ToastController.shared.show(Toast(systemImage: "qrcode", title: "No QR code found"), near: location)
                        return
                    }
                    FileActions.copyText(codes.joined(separator: "\n"))
                    let title = codes.count == 1 ? "Copied QR code" : "Copied \(codes.count) QR codes"
                    ToastController.shared.show(Toast(systemImage: "qrcode", title: title, subtitle: codes[0]), near: location, for: .seconds(3))
                } catch {
                    ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "Couldn’t read QR code", subtitle: error.localizedDescription), near: location)
                }
            }

        case .combinePDF:
            runner.run(title: "Combining into PDF", jobs: [urls], near: location, sourceShelfID: sourceShelfID) { sources, progress in
                [try await PDFTools.combine(sources, progress: progress)]
            }

        case .mute:
            runner.run(title: "Removing audio", jobs: urls.map { [$0] }, keepsFormat: true, near: location, sourceShelfID: sourceShelfID) { sources, progress in
                [try await MediaTools.mute(sources[0], progress: progress)]
            }

        case .reverse:
            runner.run(title: "Reversing", jobs: urls.map { [$0] }, keepsFormat: true, near: location, sourceShelfID: sourceShelfID) { sources, progress in
                [try await MediaTools.reverse(sources[0], progress: progress)]
            }

        case .mediaMetadata:
            runner.run(title: "Removing metadata", jobs: urls.map { [$0] }, keepsFormat: true, near: location, sourceShelfID: sourceShelfID) { sources, progress in
                [try await MediaTools.stripMetadata(sources[0], progress: progress)]
            }

        case .mono:
            runner.run(title: "Mixing to mono", jobs: urls.map { [$0] }, keepsFormat: true, near: location, sourceShelfID: sourceShelfID) { sources, progress in
                [try await MediaTools.mono(sources[0], progress: progress)]
            }

        case .normalize:
            runner.run(title: "Evening out loudness", jobs: urls.map { [$0] }, keepsFormat: true, near: location, sourceShelfID: sourceShelfID) { sources, progress in
                [try await MediaTools.normalizeLoudness(sources[0], progress: progress)]
            }

        case .grayscale:
            runner.run(title: "Making grayscale", jobs: urls.map { [$0] }, keepsFormat: true, near: location, sourceShelfID: sourceShelfID) { sources, progress in
                [try await MediaTools.grayscale(sources[0], progress: progress)]
            }

        case .ocr:
            EditorWindowController.present(size: OCREditor.windowSize, near: location, sourceShelfID: sourceShelfID) { OCREditor(urls: urls, actions: $0) }

        case .transcribe:
            runner.run(title: "Transcribing", jobs: urls.map { [$0] }, near: location, sourceShelfID: sourceShelfID) { sources, progress in
                try await Transcription.transcribe(sources[0], progress: progress)
            }

        case .pdfImages:
            EditorWindowController.present(size: PDFImagesEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { PDFImagesEditor(url: first, actions: $0) }

        case .icon:
            runner.run(title: "Making icons", jobs: urls.map { [$0] }, near: location, sourceShelfID: sourceShelfID) { sources, _ in
                try await IconMaker.make(sources[0])
            }

        case .gifLoop:
            EditorWindowController.present(size: GIFLoopEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { GIFLoopEditor(urls: urls, actions: $0) }

        case .prettyPrint:
            runner.run(title: "Pretty printing", jobs: urls.map { [$0] }, unchangedLabel: "already formatted", near: location, sourceShelfID: sourceShelfID) { sources, _ in
                try await PrettyPrint.format(sources[0]).map { [$0] } ?? []
            }

        case .sqliteTables:
            EditorWindowController.present(size: SQLiteTablesEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { SQLiteTablesEditor(url: first, actions: $0) }

        case .organizePages:
            EditorWindowController.present(size: PDFPagesEditor.windowSize(for: urls.count), near: location, sourceShelfID: sourceShelfID) { PDFPagesEditor(urls: urls, actions: $0) }
        case .splitPDF:
            EditorWindowController.present(size: PDFSplitEditor.windowSize(for: urls.count), near: location, sourceShelfID: sourceShelfID) { PDFSplitEditor(urls: urls, actions: $0) }
        case .compressPDF:
            EditorWindowController.present(size: PDFCompressEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { PDFCompressEditor(urls: urls, actions: $0) }
        case .pdfMetadata:
            EditorWindowController.present(size: PDFMetadataEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { PDFMetadataEditor(urls: urls, actions: $0) }
        case .makeFillable:
            EditorWindowController.present(size: MakeFillableEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { MakeFillableEditor(url: first, actions: $0) }

        case .trim:
            EditorWindowController.present(size: MediaTrimEditor.windowSize(for: urls.count), near: location, sourceShelfID: sourceShelfID) { MediaTrimEditor(urls: urls, actions: $0) }
        case .compressAudio:
            EditorWindowController.present(size: AudioCompressEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { AudioCompressEditor(urls: urls, actions: $0) }
        case .export:
            EditorWindowController.present(size: MediaExportEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { MediaExportEditor(urls: urls, actions: $0) }
        case .frameRate:
            EditorWindowController.present(size: FrameRateEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { FrameRateEditor(urls: urls, actions: $0) }
        case .fitSize:
            EditorWindowController.present(size: FitSizeEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { FitSizeEditor(urls: urls, actions: $0) }
        case .volume:
            EditorWindowController.present(size: MediaVolumeEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { MediaVolumeEditor(urls: urls, actions: $0) }
        case .speed:
            EditorWindowController.present(size: MediaSpeedEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { MediaSpeedEditor(urls: urls, actions: $0) }
        case .cropVideo:
            EditorWindowController.present(size: VideoCropEditor.windowSize(for: urls.count), near: location, sourceShelfID: sourceShelfID) { VideoCropEditor(urls: urls, actions: $0) }
        case .compressVideo:
            EditorWindowController.present(size: VideoCompressEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { VideoCompressEditor(urls: urls, actions: $0) }
        case .mergeMedia:
            EditorWindowController.present(size: MediaMergeEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { MediaMergeEditor(urls: urls, actions: $0) }
        case .splitMedia:
            EditorWindowController.present(size: MediaSplitEditor.windowSize(for: urls.count), near: location, sourceShelfID: sourceShelfID) { MediaSplitEditor(urls: urls, actions: $0) }
        case .rotateVideo:
            EditorWindowController.present(size: VideoRotateEditor.windowSize(for: urls.count), near: location, sourceShelfID: sourceShelfID) { VideoRotateEditor(urls: urls, actions: $0) }
        case .stillFrame:
            showOneFileNote(tool, urls: urls)
            EditorWindowController.present(size: StillFrameEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { StillFrameEditor(url: first, actions: $0) }
        }
    }

    private static func openImageEditor(_ tool: FileTool, with urls: [URL], near location: NSPoint, sourceShelfID: Shelf.ID?) {
        let images: [EditableImage]
        do {
            images = try urls.map(EditableImage.load)
        } catch {
            ToastController.shared.show(Toast(systemImage: "exclamationmark.triangle", title: "Couldn’t open image", subtitle: error.localizedDescription))
            return
        }
        guard !images.isEmpty else { return }

        switch tool {
        case .crop:
            EditorWindowController.present(size: CropEditor.windowSize(for: images.count), near: location, sourceShelfID: sourceShelfID) { CropEditor(images: images, actions: $0) }
        case .addBackground:
            EditorWindowController.present(size: AddBackgroundEditor.windowSize(for: images.count), near: location, sourceShelfID: sourceShelfID) { AddBackgroundEditor(images: images, actions: $0) }
        case .annotate:
            EditorWindowController.present(size: AnnotateEditor.windowSize(for: images.count), near: location, sourceShelfID: sourceShelfID) { AnnotateEditor(images: images, actions: $0) }
        case .redact:
            EditorWindowController.present(size: RedactEditor.windowSize(for: images.count), near: location, sourceShelfID: sourceShelfID) { RedactEditor(images: images, actions: $0) }
        case .edit:
            EditorWindowController.present(size: AdjustEditor.windowSize(for: images.count), near: location, sourceShelfID: sourceShelfID) { AdjustEditor(images: images, actions: $0) }
        case .compress:
            EditorWindowController.present(size: CompressEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { CompressEditor(images: images, actions: $0) }
        case .metadata:
            EditorWindowController.present(size: MetadataEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { MetadataEditor(images: images, actions: $0) }
        case .resize:
            EditorWindowController.present(size: ResizeEditor.windowSize, near: location, sourceShelfID: sourceShelfID) { ResizeEditor(images: images, actions: $0) }
        case .removeBackground:
            EditorWindowController.present(size: RemoveBackgroundEditor.windowSize(for: images.count), near: location, sourceShelfID: sourceShelfID) { RemoveBackgroundEditor(images: images, actions: $0) }
        default:
            break
        }
    }

    /// Still Frame works on one video; the other editors take several.
    private static func showOneFileNote(_ tool: FileTool, urls: [URL]) {
        guard urls.count > 1 else { return }
        ToastController.shared.show(Toast(systemImage: "info.circle", title: "\(tool.title) works on one file", subtitle: "Opened \(urls[0].lastPathComponent)"))
    }
}
