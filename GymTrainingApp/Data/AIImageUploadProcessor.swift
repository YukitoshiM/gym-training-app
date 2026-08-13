import UIKit

enum AIImageUploadProcessor {
    static let maximumLongEdge: CGFloat = 1_600
    static let jpegQuality: CGFloat = 0.8

    static func jpegData(from sourceData: Data) throws -> Data {
        guard let sourceImage = UIImage(data: sourceData),
              sourceImage.size.width > 0,
              sourceImage.size.height > 0 else {
            throw AIClientError.invalidImage
        }

        let scale = min(1, maximumLongEdge / max(sourceImage.size.width, sourceImage.size.height))
        let targetSize = CGSize(
            width: max(1, (sourceImage.size.width * scale).rounded()),
            height: max(1, (sourceImage.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let data = image.jpegData(compressionQuality: jpegQuality) else {
            throw AIClientError.invalidImage
        }
        return data
    }
}
