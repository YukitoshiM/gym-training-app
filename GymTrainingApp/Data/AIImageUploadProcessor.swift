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

    static func bodyPhotoContactSheet(
        _ photos: [BodyPhotoAnalysisInput],
        canvasSize: CGFloat = 1_200
    ) throws -> Data {
        guard !photos.isEmpty else { throw AIClientError.invalidImage }
        let sourceByAngle = Dictionary(uniqueKeysWithValues: photos.map { ($0.angle, $0.imageData) })
        let gutter: CGFloat = 8
        let cellSize = (canvasSize - gutter) / 2
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: canvasSize, height: canvasSize),
            format: format
        )
        let image = renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

            for (index, angle) in BodyPhotoAngle.allCases.enumerated() {
                let column = CGFloat(index % 2)
                let row = CGFloat(index / 2)
                let cell = CGRect(
                    x: column * (cellSize + gutter),
                    y: row * (cellSize + gutter),
                    width: cellSize,
                    height: cellSize
                )
                UIColor.secondarySystemBackground.setFill()
                context.fill(cell)
                guard let data = sourceByAngle[angle], let source = UIImage(data: data) else {
                    continue
                }
                source.draw(in: aspectFitRect(for: source.size, inside: cell.insetBy(dx: 4, dy: 4)))
            }
        }
        guard let data = image.jpegData(compressionQuality: 0.72) else {
            throw AIClientError.invalidImage
        }
        return data
    }

    private static func aspectFitRect(for sourceSize: CGSize, inside bounds: CGRect) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return bounds }
        let scale = min(bounds.width / sourceSize.width, bounds.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
