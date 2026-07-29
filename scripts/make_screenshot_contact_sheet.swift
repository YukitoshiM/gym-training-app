import AppKit
import Foundation

guard CommandLine.arguments.count == 5,
      let columns = Int(CommandLine.arguments[3]),
      let itemWidth = Int(CommandLine.arguments[4]) else {
    fputs("Usage: swift make_screenshot_contact_sheet.swift <input-dir> <output.png> <columns> <item-width>\n", stderr)
    exit(1)
}

let inputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let fileManager = FileManager.default
let imageURLs = try fileManager.contentsOfDirectory(
    at: inputDirectory,
    includingPropertiesForKeys: nil
)
.filter { $0.pathExtension.lowercased() == "png" }
.sorted { $0.lastPathComponent < $1.lastPathComponent }

guard let sampleURL = imageURLs.first,
      let sampleImage = NSImage(contentsOf: sampleURL) else {
    fputs("No PNG images found in \(inputDirectory.path)\n", stderr)
    exit(1)
}

let gap = 24
let outerPadding = 32
let labelHeight = 42
let aspectRatio = sampleImage.size.height / sampleImage.size.width
let itemHeight = Int((CGFloat(itemWidth) * aspectRatio).rounded())
let rows = Int(ceil(Double(imageURLs.count) / Double(columns)))
let canvasWidth = outerPadding * 2 + columns * itemWidth + (columns - 1) * gap
let canvasHeight = outerPadding * 2 + rows * (itemHeight + labelHeight) + (rows - 1) * gap

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasWidth,
    pixelsHigh: canvasHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: canvasWidth * 4,
    bitsPerPixel: 32
) else {
    fputs("Could not create bitmap context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = context

NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight).fill()

let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center
paragraphStyle.lineBreakMode = .byTruncatingMiddle
let textAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
    .paragraphStyle: paragraphStyle
]

for (index, imageURL) in imageURLs.enumerated() {
    guard let image = NSImage(contentsOf: imageURL) else { continue }
    let column = index % columns
    let row = index / columns
    let x = outerPadding + column * (itemWidth + gap)
    let top = canvasHeight - outerPadding - row * (itemHeight + labelHeight + gap)
    let imageY = top - itemHeight

    NSColor.white.setFill()
    NSRect(x: x - 1, y: imageY - 1, width: itemWidth + 2, height: itemHeight + 2).fill()
    image.draw(
        in: NSRect(x: x, y: imageY, width: itemWidth, height: itemHeight),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

    let label = imageURL.deletingPathExtension().lastPathComponent
    label.draw(
        in: NSRect(x: x, y: imageY - labelHeight, width: itemWidth, height: labelHeight - 4),
        withAttributes: textAttributes
    )
}

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode PNG\n", stderr)
    exit(1)
}
try pngData.write(to: outputURL)
