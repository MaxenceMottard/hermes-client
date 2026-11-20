import AVFoundation
import CoreTransferable
import Foundation
import HermesAPI
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Turns picked photos into `ImageAttachment`s and makes thumbnails from them.
///
/// Photos are downscaled to `maxDimension` and re-encoded as JPEG, which keeps each request well under
/// the instance's 10 MB body limit.
enum ImageAttachmentLoader {
    static let maxDimension = 2048
    static let jpegQuality = 0.8
    /// Frames taken from a picked video, before the per-message limit is applied.
    static let videoFrameCount = 4

    /// Photos give one attachment. A video gives up to `videoFrameCount` frames, capped at `maxCount`.
    static func attachments(from item: PhotosPickerItem, maxCount: Int) async -> [ImageAttachment] {
        guard maxCount > 0 else { return [] }
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else { return [] }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            let frames = (try? await videoFrames(at: movie.url, count: min(videoFrameCount, maxCount))) ?? []
            return frames.compactMap { jpegAttachment(from: $0) }
        }
        guard let raw = try? await item.loadTransferable(type: Data.self),
            let attachment = jpegAttachment(from: raw)
        else { return [] }
        return [attachment]
    }

    /// `count` frames spread evenly over the video, each at the centre of its segment.
    static func videoFrames(at url: URL, count: Int) async throws -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        var frames: [CGImage] = []
        for index in 0 ..< count {
            let seconds = duration * (Double(index) + 0.5) / Double(count)
            let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            frames.append(image)
        }
        return frames
    }

    static func jpegAttachment(from image: CGImage) -> ImageAttachment? {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ImageAttachment(mimeType: "image/jpeg", data: output as Data)
    }

    static func jpegAttachment(from data: Data) -> ImageAttachment? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ImageAttachment(mimeType: "image/jpeg", data: output as Data)
    }

    /// A small preview of image data, or `nil` when the data is not a readable image.
    static func thumbnail(for data: Data, maxPixelSize: Int = 240) -> Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return Image(decorative: cgImage, scale: 1)
    }
}

/// A square image preview. `onRemove` adds a remove button for the composer.
struct AttachmentThumbnail: View {
    let data: Data
    var onRemove: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            (ImageAttachmentLoader.thumbnail(for: data) ?? Image(systemName: "photo"))
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if let onRemove {
                Button("Remove image", systemImage: "xmark.circle.fill") {
                    onRemove()
                }
                .labelStyle(.iconOnly)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
    }
}

/// A movie picked from the library, copied to a temporary file that the caller deletes.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}
