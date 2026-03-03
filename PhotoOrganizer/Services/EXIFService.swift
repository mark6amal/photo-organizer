import Foundation
import ImageIO

struct EXIFMetadata: Sendable {
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var aperture: String?
    var shutterSpeed: String?
    var iso: String?
    var focalLength: String?
    var captureDate: Date?
}

enum EXIFService {
    static func captureDate(for url: URL) -> Date? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        // EXIF DateTimeOriginal
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            return parse(raw)
        }

        // TIFF DateTime fallback
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let raw = tiff[kCGImagePropertyTIFFDateTime] as? String {
            return parse(raw)
        }

        return nil
    }

    static func metadata(for url: URL) -> EXIFMetadata {
        var meta = EXIFMetadata()
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return meta }

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        meta.cameraMake = tiff?[kCGImagePropertyTIFFMake] as? String
        meta.cameraModel = tiff?[kCGImagePropertyTIFFModel] as? String
        meta.lensModel = exif?[kCGImagePropertyExifLensModel] as? String

        if let fNum = exif?[kCGImagePropertyExifFNumber] as? Double {
            meta.aperture = String(format: "f/%.1g", fNum)
        }

        if let expTime = exif?[kCGImagePropertyExifExposureTime] as? Double, expTime > 0 {
            if expTime >= 1 {
                meta.shutterSpeed = String(format: "%.1fs", expTime)
            } else {
                meta.shutterSpeed = "1/\(Int((1.0 / expTime).rounded()))s"
            }
        }

        if let isoList = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int],
           let first = isoList.first {
            meta.iso = "ISO \(first)"
        }

        if let fl = exif?[kCGImagePropertyExifFocalLength] as? Double {
            meta.focalLength = "\(Int(fl))mm"
        }

        if let raw = exif?[kCGImagePropertyExifDateTimeOriginal] as? String {
            meta.captureDate = parse(raw)
        } else if let raw = tiff?[kCGImagePropertyTIFFDateTime] as? String {
            meta.captureDate = parse(raw)
        }

        return meta
    }

    private static func parse(_ string: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return fmt.date(from: string)
    }
}
