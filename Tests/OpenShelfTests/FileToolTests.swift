import AppKit
import Foundation
import Testing
@testable import OpenShelf

struct FileToolTests {
    private let ffmpeg = ExternalTools(ffmpeg: URL(fileURLWithPath: "/usr/bin/true"))

    private func urls(_ names: String...) -> [URL] {
        names.map { URL(fileURLWithPath: "/tmp/\($0)") }
    }

    @Test func imagesGetTheVideoToolOrderPlusReadQR() {
        #expect(FileTool.available(for: urls("a.jpg"), tools: ExternalTools()) == [.compress, .metadata, .edit, .annotate, .addBackground, .crop, .resize, .removeBackground, .redact, .readQR, .ocr, .icon])
    }

    @Test func severalImagesCanBeCombined() {
        #expect(FileTool.available(for: urls("a.jpg", "b.png"), tools: ExternalTools()).last == .combinePDF)
    }

    @Test func singlePDFGetsPageTools() {
        #expect(FileTool.available(for: urls("a.pdf"), tools: ExternalTools()) == [.organizePages, .splitPDF, .pdfImages, .compressPDF, .pdfMetadata, .ocr])
    }

    @Test func severalPDFsGetCombineAndThePageTools() {
        #expect(FileTool.available(for: urls("a.pdf", "b.pdf"), tools: ExternalTools()) == [.combinePDF, .organizePages, .splitPDF, .compressPDF, .pdfMetadata, .ocr])
    }

    @Test func imagesAndPDFsTogetherOfferCombineAndOCR() {
        #expect(FileTool.available(for: urls("a.pdf", "b.jpg"), tools: ExternalTools()) == [.combinePDF, .ocr])
    }

    @Test func mediaTools() {
        #expect(FileTool.available(for: urls("a.mov"), tools: ExternalTools()) == [.trim, .speed, .cropVideo, .rotateVideo, .splitMedia, .compressVideo, .mute, .stillFrame, .grayscale, .transcribe])
        #expect(FileTool.available(for: urls("a.mp3"), tools: ExternalTools()) == [.trim, .speed, .splitMedia, .compressAudio, .export, .transcribe])
    }

    @Test func severalMediaFilesCanBeMerged() {
        #expect(FileTool.available(for: urls("a.mov", "b.mp4"), tools: ExternalTools()).first == .mergeMedia)
        #expect(FileTool.available(for: urls("a.mp3", "b.m4a"), tools: ExternalTools()) == [.mergeMedia, .trim, .speed, .splitMedia, .compressAudio, .export, .transcribe])
        #expect(!FileTool.available(for: urls("a.mov", "b.mp3"), tools: ExternalTools()).contains(.mergeMedia))
    }

    @Test func convertFirstToastNamesTheFormatToConvertTo() {
        let video = FileTool.convertFirstToast(for: urls("a.mkv"), convertKeys: "⇧", tools: ffmpeg)
        #expect(video.title == "Convert to MP4 first")
        #expect(video.subtitle == "Tap ⇧ while dragging to convert")
        #expect(FileTool.convertFirstToast(for: urls("a.wma"), convertKeys: "⇧", tools: ffmpeg).title == "Convert to M4A first")
        #expect(FileTool.convertFirstToast(for: urls("a.webm", "b.wma"), convertKeys: "⇧", tools: ffmpeg).title == "Convert to MP4 or M4A first")
        // The Convert wheel's trigger can be changed in Settings.
        #expect(FileTool.convertFirstToast(for: urls("a.avi"), convertKeys: "⌃⌥", tools: ffmpeg).subtitle == "Tap ⌃⌥ while dragging to convert")
    }

    @Test func convertFirstToastFitsOnOneLine() {
        // The toast shows one line each: about 30 characters of subtitle fit.
        let toast = FileTool.convertFirstToast(for: urls("a.webm", "b.wma"), convertKeys: "⇧⌥", tools: ffmpeg)
        #expect(toast.title.count <= 28)
        #expect((toast.subtitle ?? "").count <= 34)
    }

    @Test func mediaToolsOnlyForFormatsTheMediaFrameworkEdits() {
        for name in ["a.mkv", "a.webm", "a.avi", "a.wmv", "a.flv", "a.wma"] {
            #expect(FileTool.available(for: urls(name), tools: ExternalTools()).isEmpty, "\(name) should not offer tools")
            #expect(FileTool.needsConversionForTools(urls(name), tools: ExternalTools()))
        }
        // With ffmpeg, MKV, WebM and AVI are edited through it; WMV, FLV and WMA still convert first.
        for name in ["a.mkv", "a.webm", "a.avi"] {
            #expect(FileTool.available(for: urls(name), tools: ffmpeg).contains(.trim), "\(name)")
            #expect(!FileTool.needsConversionForTools(urls(name), tools: ffmpeg))
        }
        for name in ["a.wmv", "a.flv", "a.wma"] {
            #expect(FileTool.available(for: urls(name), tools: ffmpeg).isEmpty, "\(name)")
        }
        #expect(FileTool.available(for: urls("a.mp4", "b.mkv"), tools: ExternalTools()).isEmpty)
        #expect(!FileTool.available(for: urls("a.ogg"), tools: ExternalTools()).isEmpty)
        #expect(!FileTool.needsConversionForTools(urls("a.mp4")))
        #expect(!FileTool.needsConversionForTools(urls("a.jpg")))
    }

    @Test func otherFilesHaveNoTools() {
        #expect(FileTool.available(for: urls("a.txt"), tools: ExternalTools()).isEmpty)
        #expect(FileTool.available(for: []).isEmpty)
    }

    @Test func everyToolHasASymbol() {
        for tool in FileTool.allCases {
            #expect(NSImage(systemSymbolName: tool.systemImage, accessibilityDescription: nil) != nil, "\(tool.systemImage)")
        }
    }
}
