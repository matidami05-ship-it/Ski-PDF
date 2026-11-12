import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins

/// Image compression, resizing, format conversion and metadata removal using ImageIO.
enum ImageEngine {

    enum Format: String, CaseIterable, Identifiable {
        case jpeg = "JPEG", png = "PNG", heic = "HEIC"
        var id: String { rawValue }
        var type: UTType {
            switch self {
            case .jpeg: return .jpeg
            case .png: return .png
            case .heic: return .heic
            }
        }
        var ext: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            case .heic: return "heic"
            }
        }
        var lossy: Bool { self != .png }

        static func of(_ data: Data) -> Format {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil), let t = CGImageSourceGetType(src) as String? else { return .jpeg }
            if let ut = UTType(t) {
                if ut.conforms(to: .png) { return .png }
                if ut.conforms(to: .heic) || ut.conforms(to: .heif) { return .heic }
            }
            return .jpeg
        }
    }

    struct Info {
        var pixelWidth: Int
        var pixelHeight: Int
        var hasGPS: Bool
        var camera: String?
        var date: String?
        var bytes: Int
    }

    static func info(_ data: Data) -> Info? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let make = tiff?[kCGImagePropertyTIFFMake] as? String
        let model = tiff?[kCGImagePropertyTIFFModel] as? String
        let camera = [make, model].compactMap { $0 }.joined(separator: " ")
        var w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        var h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        if let o = props[kCGImagePropertyOrientation] as? Int, o >= 5 { swap(&w, &h) }
        return Info(pixelWidth: w, pixelHeight: h,
                    hasGPS: props[kCGImagePropertyGPSDictionary] != nil,
                    camera: camera.isEmpty ? nil : camera,
                    date: exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
                    bytes: data.count)
    }

    /// Decodes an image with its orientation applied, optionally downscaled so the longest side ≤ maxPixel.
    static func decode(_ data: Data, maxPixel: Int? = nil) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(w, h)
        let target = min(maxPixel ?? longest, longest)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, target),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Encodes an image. Metadata is only written if given (so by default everything is stripped).
    static func encode(_ image: CGImage, as format: Format, quality: CGFloat, metadata: [CFString: Any]? = nil) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, format.type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = metadata ?? [:]
        if format.lossy { props[kCGImageDestinationLossyCompressionQuality] = quality }
        props[kCGImagePropertyOrientation] = 1
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Camera/descriptive metadata worth keeping when the user doesn't ask to strip it (orientation is baked in).
    static func keptMetadata(_ data: Data) -> [CFString: Any]? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              var props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        props.removeValue(forKey: kCGImagePropertyOrientation)
        props.removeValue(forKey: kCGImagePropertyPixelWidth)
        props.removeValue(forKey: kCGImagePropertyPixelHeight)
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation)
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        return props
    }

    /// Redraws an image upright at scale 1 (fixes rotated phone photos).
    static func normalized(_ img: UIImage) -> UIImage {
        if img.imageOrientation == .up { return img }
        let format = UIGraphicsImageRendererFormat()
        format.scale = img.scale
        return UIGraphicsImageRenderer(size: img.size, format: format).image { _ in img.draw(at: .zero) }
    }

    private static let ci = CIContext(options: [.useSoftwareRenderer: false])

    static func grayscale(_ img: UIImage) -> UIImage? {
        guard let input = CIImage(image: img) else { return nil }
        let f = CIFilter.colorControls()
        f.inputImage = input
        f.saturation = 0
        guard let out = f.outputImage, let cg = ci.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// High-contrast black & white, good for scanned text.
    static func blackAndWhite(_ img: UIImage) -> UIImage? {
        guard let input = CIImage(image: img) else { return nil }
        let mono = CIFilter.colorControls()
        mono.inputImage = input
        mono.saturation = 0
        mono.contrast = 1.9
        mono.brightness = 0.08
        guard let out = mono.outputImage, let cg = ci.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Brightens and sharpens a colour scan a little.
    static func enhanced(_ img: UIImage) -> UIImage? {
        guard let input = CIImage(image: img) else { return nil }
        let c = CIFilter.colorControls()
        c.inputImage = input
        c.contrast = 1.15
        c.brightness = 0.03
        c.saturation = 1.05
        let s = CIFilter.sharpenLuminance()
        s.inputImage = c.outputImage
        s.sharpness = 0.4
        guard let out = s.outputImage, let cg = ci.createCGImage(out, from: input.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
