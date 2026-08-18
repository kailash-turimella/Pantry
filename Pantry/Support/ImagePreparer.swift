import UIKit

/// Gets photos into a shape that's cheap to send to Claude.
///
/// Claude Opus 5 accepts images up to 2576px on the long edge (~4,800 image
/// tokens each). Groceries are big obvious objects — 1568px is plenty to read a
/// label, and costs roughly a third of that. At $5/MTok that's the difference
/// between ~$0.008 and ~$0.024 per photo, which adds up over a year of shopping.
enum ImagePreparer {
    static let maxDimension: CGFloat = 1568
    static let jpegQuality: CGFloat = 0.8
    /// The API caps a request at 32MB; we stay far below it.
    static let maxBytes = 3_500_000

    struct Prepared {
        let base64: String
        let mediaType: String
        let byteCount: Int
    }

    static func prepare(_ image: UIImage) -> Prepared? {
        let resized = resize(image, maxDimension: maxDimension)
        var quality = jpegQuality
        var data = resized.jpegData(compressionQuality: quality)

        while let current = data, current.count > maxBytes, quality > 0.3 {
            quality -= 0.15
            data = resized.jpegData(compressionQuality: quality)
        }

        guard let data else { return nil }
        return Prepared(
            base64: data.base64EncodedString(),
            mediaType: "image/jpeg",
            byteCount: data.count
        )
    }

    /// Prepares already-encoded bytes (e.g. a downloaded reel thumbnail).
    static func prepare(data: Data) -> Prepared? {
        guard let image = UIImage(data: data) else { return nil }
        return prepare(image)
    }

    static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxDimension else { return image.normalizedOrientation() }

        let scale = maxDimension / longEdge
        let target = CGSize(width: (image.size.width * scale).rounded(),
                            height: (image.size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

private extension UIImage {
    /// Camera photos carry an EXIF orientation that JPEG re-encoding respects but
    /// the model shouldn't have to reason about — bake it in.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
