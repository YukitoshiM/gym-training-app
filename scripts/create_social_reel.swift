import AppKit
import AVFoundation
import CoreImage
import CoreGraphics
import CoreVideo
import Foundation

private let width = 1080
private let height = 1920
private let fps: Int32 = 30
private let duration = 18.0

private struct Scene {
    let start: Double
    let end: Double
    let eyebrow: String
    let headline: String
    let detail: String
    let image: String?
    let secondaryImage: String?
}

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let locale = CommandLine.arguments.dropFirst().first == "ja" ? "ja" : "en"
private let outputURL = root.appendingPathComponent("docs/social/bodymode-beta-reel-\(locale).mp4")
private let silentOutputURL = root.appendingPathComponent("docs/social/bodymode-beta-reel-\(locale)-silent.mp4")
private let testFlightURL = "https://testflight.apple.com/join/ApPJPygJ"

private let englishScenes = [
    Scene(start: 0.0, end: 2.6,
          eyebrow: "BETA TESTERS WANTED",
          headline: "Can an AI coach\nend the guesswork?",
          detail: "Try BodyMode before launch and tell us.",
          image: "GymTrainingApp/Assets.xcassets/CoachAvatarNia.imageset/coach-nia.jpg",
          secondaryImage: nil),
    Scene(start: 2.6, end: 5.2,
          eyebrow: "THE PROBLEM",
          headline: "You track it all.\nStill unsure what to do.",
          detail: "Most apps record. The daily decision is still yours.",
          image: "docs/social/screenshots/en/08-record-hub.png",
          secondaryImage: nil),
    Scene(start: 5.2, end: 7.8,
          eyebrow: "AI SEES THE WHOLE PICTURE",
          headline: "One AI coach.\nYour whole body.",
          detail: "Training, recovery, nutrition and body progress.",
          image: "GymTrainingApp/Assets.xcassets/CoachAvatarNia.imageset/coach-nia.jpg",
          secondaryImage: nil),
    Scene(start: 7.8, end: 10.4,
          eyebrow: "AI BUILDS THE ACTION PLAN",
          headline: "Today's three.\nA workout ready to start.",
          detail: "Ask why, discuss it, and adjust the plan.",
          image: "docs/social/screenshots/en/01-home-dashboard.png",
          secondaryImage: nil),
    Scene(start: 10.4, end: 13.0,
          eyebrow: "IPHONE + APPLE WATCH",
          headline: "Train from\nyour wrist.",
          detail: "Sets, rest timers and live progress.",
          image: "docs/social/screenshots/en/04-workout-session.png",
          secondaryImage: "docs/social/screenshots/en/02-active-set.png"),
    Scene(start: 13.0, end: 15.6,
          eyebrow: "AI LEARNS AND ADAPTS",
          headline: "Your result updates\ntomorrow's plan.",
          detail: "The AI coach learns what works for you.",
          image: "docs/social/screenshots/en/06-body-progress.png",
          secondaryImage: nil),
    Scene(start: 15.6, end: 18.0,
          eyebrow: "BECOME A BETA TESTER",
          headline: "Test the AI coach.\nTell us the truth.",
          detail: "Free on TestFlight. Help shape BodyMode.",
          image: "GymTrainingApp/Assets.xcassets/AppIcon.appiconset/GymTrainingAppIcon.png",
          secondaryImage: nil)
]

private let japaneseScenes = [
    Scene(start: 0.0, end: 2.6,
          eyebrow: "BETA TESTERS WANTED",
          headline: "AIトレーナーの\nベータテスター募集。",
          detail: "迷う時間を、動く時間へ変えられるか？",
          image: "GymTrainingApp/Assets.xcassets/CoachAvatarNia.imageset/coach-nia.jpg",
          secondaryImage: nil),
    Scene(start: 2.6, end: 5.2,
          eyebrow: "THE PROBLEM",
          headline: "記録しても、\n今日何をするか迷う。",
          detail: "多くのアプリは、記録した後の判断をしてくれない。",
          image: "docs/app-store/screenshots/08-record-hub.png",
          secondaryImage: nil),
    Scene(start: 5.2, end: 7.8,
          eyebrow: "AI SEES THE WHOLE PICTURE",
          headline: "1人のAIが、\n身体全体をまとめて見る。",
          detail: "運動・回復・食事・体型まで確認します。",
          image: "GymTrainingApp/Assets.xcassets/CoachAvatarNia.imageset/coach-nia.jpg",
          secondaryImage: nil),
    Scene(start: 7.8, end: 10.4,
          eyebrow: "AI BUILDS THE ACTION PLAN",
          headline: "AIが今日の3つと\nメニューを自動作成。",
          detail: "理由を聞いて、相談しながら調整できます。",
          image: "docs/app-store/screenshots/01-home-dashboard.png",
          secondaryImage: nil),
    Scene(start: 10.4, end: 13.0,
          eyebrow: "IPHONE + APPLE WATCH",
          headline: "ジムではWatchで\nそのまま実行。",
          detail: "セット記録と休憩タイマーを手元で。",
          image: "docs/app-store/screenshots/04-workout-session.png",
          secondaryImage: "docs/app-store/watch-screenshots/02-active-set.png"),
    Scene(start: 13.0, end: 15.6,
          eyebrow: "AI LEARNS AND ADAPTS",
          headline: "実績から学び、\n明日の計画を更新。",
          detail: "AIトレーナーが合う進め方を見つけます。",
          image: "docs/app-store/screenshots/06-body-progress.png",
          secondaryImage: nil),
    Scene(start: 15.6, end: 18.0,
          eyebrow: "BECOME A BETA TESTER",
          headline: "AIトレーナーを試して、\n本音を聞かせてください。",
          detail: "TestFlightで無料ベータ公開中。",
          image: "GymTrainingApp/Assets.xcassets/AppIcon.appiconset/GymTrainingAppIcon.png",
          secondaryImage: nil)
]

private let scenes = locale == "ja" ? japaneseScenes : englishScenes

private let navy = NSColor(calibratedRed: 0.018, green: 0.064, blue: 0.135, alpha: 1).cgColor
private let cobalt = NSColor(calibratedRed: 0.14, green: 0.34, blue: 0.95, alpha: 1).cgColor
private let pale = NSColor(calibratedRed: 0.90, green: 0.94, blue: 1.0, alpha: 1).cgColor
private let muted = NSColor(calibratedRed: 0.67, green: 0.73, blue: 0.84, alpha: 1).cgColor

private func image(at relativePath: String) -> CGImage? {
    let url = root.appendingPathComponent(relativePath)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

private let testFlightQRCode: CGImage? = {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(Data(testFlightURL.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else { return nil }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(scaled, from: scaled.extent)
}()

private let loadedImages: [String: CGImage] = {
    var result: [String: CGImage] = [:]
    for path in scenes.flatMap({ [$0.image, $0.secondaryImage].compactMap { $0 } }) {
        if result[path] == nil, let value = image(at: path) { result[path] = value }
    }
    return result
}()

private func font(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

private func drawText(_ text: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight,
                      color: NSColor, alignment: NSTextAlignment = .left,
                      lineHeight: CGFloat? = nil, alpha: CGFloat = 1) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.minimumLineHeight = lineHeight ?? size * 1.18
    paragraph.maximumLineHeight = lineHeight ?? size * 1.18
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font(size, weight: weight),
        .foregroundColor: color.withAlphaComponent(alpha),
        .paragraphStyle: paragraph,
        .kern: 0
    ]
    NSAttributedString(string: text, attributes: attributes).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
}

private func roundedRect(_ context: CGContext, rect: CGRect, radius: CGFloat,
                         fill: CGColor, stroke: CGColor? = nil, lineWidth: CGFloat = 1) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(path)
    context.setFillColor(fill)
    context.fillPath()
    if let stroke {
        context.addPath(path)
        context.setStrokeColor(stroke)
        context.setLineWidth(lineWidth)
        context.strokePath()
    }
}

private func drawImage(_ cgImage: CGImage, in rect: CGRect, radius: CGFloat, context: CGContext, alpha: CGFloat) {
    context.saveGState()
    context.setAlpha(alpha)
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 36,
                      color: NSColor.black.withAlphaComponent(0.38).cgColor)
    roundedRect(context, rect: rect, radius: radius,
                fill: NSColor(calibratedWhite: 1, alpha: 0.08).cgColor,
                stroke: NSColor.white.withAlphaComponent(0.15).cgColor, lineWidth: 2)
    context.restoreGState()

    let imageRatio = CGFloat(cgImage.width) / CGFloat(cgImage.height)
    let rectRatio = rect.width / rect.height
    var target = rect
    if imageRatio > rectRatio {
        target.size.height = rect.width / imageRatio
        target.origin.y += (rect.height - target.height) / 2
    } else {
        target.size.width = rect.height * imageRatio
        target.origin.x += (rect.width - target.width) / 2
    }

    context.saveGState()
    context.setAlpha(alpha)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.draw(cgImage, in: target)
    context.restoreGState()
}

private func sceneAlpha(time: Double, scene: Scene) -> CGFloat {
    let fade = 0.28
    let fadeIn = min(1, max(0, (time - scene.start) / fade))
    let fadeOut = min(1, max(0, (scene.end - time) / fade))
    return CGFloat(min(fadeIn, fadeOut))
}

private func renderFrame(context: CGContext, time: Double) {
    context.setFillColor(navy)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    context.saveGState()
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.035).cgColor)
    context.setLineWidth(2)
    for x in stride(from: -1600, through: 1800, by: 180) {
        context.move(to: CGPoint(x: x, y: 0))
        context.addLine(to: CGPoint(x: x + 900, y: height))
    }
    context.strokePath()
    context.restoreGState()

    guard let scene = scenes.first(where: { time >= $0.start && time < $0.end }) ?? scenes.last else { return }
    let alpha = sceneAlpha(time: time, scene: scene)
    let progress = CGFloat((time - scene.start) / (scene.end - scene.start))
    let lift = 18 * (1 - min(1, progress * 3))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    let betaBadge = CGRect(x: 768, y: 1810, width: 240, height: 54)
    roundedRect(context, rect: betaBadge, radius: 27,
                fill: NSColor(cgColor: cobalt)!.withAlphaComponent(0.18).cgColor,
                stroke: NSColor(cgColor: cobalt)!.withAlphaComponent(0.72).cgColor,
                lineWidth: 2)
    drawText("AI COACH BETA", in: CGRect(x: betaBadge.minX, y: betaBadge.minY + 12, width: betaBadge.width, height: 34),
             size: 20, weight: .bold, color: NSColor(cgColor: pale)!, alignment: .center)

    drawText(scene.eyebrow, in: CGRect(x: 72, y: 1755 + lift, width: 936, height: 45),
             size: 27, weight: .semibold, color: NSColor(cgColor: cobalt)!, alpha: alpha)
    drawText(scene.headline, in: CGRect(x: 72, y: 1470 + lift, width: 936, height: 260),
             size: scene.start == 0 ? 78 : 72, weight: .bold, color: .white,
             lineHeight: scene.start == 0 ? 92 : 84, alpha: alpha)
    drawText(scene.detail, in: CGRect(x: 74, y: 1400 + lift, width: 930, height: 60),
             size: 31, weight: .medium, color: NSColor(cgColor: muted)!, alpha: alpha)

    if let path = scene.image, let cgImage = loadedImages[path] {
        let imageRatio = CGFloat(cgImage.width) / CGFloat(cgImage.height)
        let isSquareArtwork = abs(imageRatio - 1) < 0.1
        if isSquareArtwork {
            let isCoach = path.contains("CoachAvatar")
            let iconSize: CGFloat = isCoach ? 560 : 420
            let iconRect = CGRect(x: (CGFloat(width) - iconSize) / 2,
                                  y: isCoach ? 560 : 690,
                                  width: iconSize, height: iconSize)
            drawImage(cgImage, in: iconRect, radius: iconSize * 0.22, context: context, alpha: alpha)
        } else {
            let scale = 1 + 0.018 * progress
            let base = CGRect(x: 172, y: 70, width: 736, height: 1270)
            let rect = base.insetBy(dx: -base.width * (scale - 1) / 2, dy: -base.height * (scale - 1) / 2)
            drawImage(cgImage, in: rect, radius: 48, context: context, alpha: alpha)
        }
    }

    if let path = scene.secondaryImage, let cgImage = loadedImages[path] {
        let watchRect = CGRect(x: 650, y: 155, width: 340, height: 405)
        drawImage(cgImage, in: watchRect, radius: 74, context: context, alpha: alpha)
    }

    if scene.image?.contains("CoachAvatar") == true {
        let labels = locale == "ja" ? ["運動", "回復", "食事"] : ["TRAINING", "RECOVERY", "NUTRITION"]
        for (index, label) in labels.enumerated() {
            let pill = CGRect(x: 76 + CGFloat(index) * 320, y: 430, width: 286, height: 74)
            roundedRect(context, rect: pill, radius: 37,
                        fill: NSColor(cgColor: cobalt)!.withAlphaComponent(0.18 * alpha).cgColor,
                        stroke: NSColor(cgColor: cobalt)!.withAlphaComponent(0.65 * alpha).cgColor,
                        lineWidth: 2)
            drawText(label, in: CGRect(x: pill.minX, y: pill.minY + 16, width: pill.width, height: 42),
                     size: 24, weight: .bold, color: NSColor(cgColor: pale)!, alignment: .center, alpha: alpha)
        }
    }

    if scene.end == duration {
        roundedRect(context, rect: CGRect(x: 255, y: 505, width: 570, height: 92), radius: 46,
                    fill: cobalt)
        let callToAction = locale == "ja" ? "ベータテスターになる" : "BECOME A BETA TESTER"
        drawText(callToAction, in: CGRect(x: 255, y: 526, width: 570, height: 52),
                 size: 30, weight: .bold, color: .white, alignment: .center, alpha: alpha)

        let scanLabel = locale == "ja" ? "QRコードから参加" : "SCAN TO JOIN"
        drawText(scanLabel, in: CGRect(x: 255, y: 445, width: 570, height: 42),
                 size: 24, weight: .semibold, color: NSColor(cgColor: muted)!, alignment: .center, alpha: alpha)

        let qrBackground = CGRect(x: 395, y: 150, width: 290, height: 290)
        roundedRect(context, rect: qrBackground, radius: 24, fill: NSColor.white.cgColor)
        if let testFlightQRCode {
            context.saveGState()
            context.setAlpha(alpha)
            context.interpolationQuality = .none
            context.draw(testFlightQRCode, in: CGRect(x: 415, y: 170, width: 250, height: 250))
            context.restoreGState()
        }
        drawText(testFlightURL, in: CGRect(x: 110, y: 88, width: 860, height: 42),
                 size: 22, weight: .medium, color: NSColor(cgColor: pale)!, alignment: .center, alpha: alpha)
    }

    NSGraphicsContext.restoreGraphicsState()
}

private func addMusic(to silentVideoURL: URL, outputURL: URL) async throws {
    let musicURL = root.appendingPathComponent("docs/social/audio/3-am-west-end.mp3")

    let videoAsset = AVURLAsset(url: silentVideoURL)
    let audioAsset = AVURLAsset(url: musicURL)
    let composition = AVMutableComposition()
    guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
          let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
          ),
          let sourceAudioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
          let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
          ) else {
        throw NSError(domain: "BodyModeReel", code: 8)
    }

    let videoDuration = try await videoAsset.load(.duration)
    try compositionVideoTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: videoDuration),
        of: sourceVideoTrack,
        at: .zero
    )
    compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
    try compositionAudioTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: videoDuration),
        of: sourceAudioTrack,
        at: .zero
    )

    let audioParameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
    let fadeDuration = CMTime(seconds: 0.8, preferredTimescale: 600)
    let fadeOutStart = CMTimeSubtract(videoDuration, fadeDuration)
    audioParameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: 0.16,
                                  timeRange: CMTimeRange(start: .zero, duration: fadeDuration))
    audioParameters.setVolume(0.16, at: fadeDuration)
    audioParameters.setVolumeRamp(fromStartVolume: 0.16, toEndVolume: 0,
                                  timeRange: CMTimeRange(start: fadeOutStart, duration: fadeDuration))
    let audioMix = AVMutableAudioMix()
    audioMix.inputParameters = [audioParameters]

    guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
        throw NSError(domain: "BodyModeReel", code: 9)
    }
    exporter.outputURL = outputURL
    exporter.outputFileType = .mp4
    exporter.audioMix = audioMix
    exporter.shouldOptimizeForNetworkUse = true
    await exporter.export()
    guard exporter.status == .completed else {
        throw exporter.error ?? NSError(domain: "BodyModeReel", code: 10)
    }
}

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: outputURL)
try? FileManager.default.removeItem(at: silentOutputURL)

let writer = try AVAssetWriter(outputURL: silentOutputURL, fileType: .mp4)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 8_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
    ]
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let attributes: [String: Any] = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
]
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
guard writer.canAdd(input) else { throw NSError(domain: "BodyModeReel", code: 1) }
writer.add(input)
guard writer.startWriting() else { throw writer.error ?? NSError(domain: "BodyModeReel", code: 2) }
writer.startSession(atSourceTime: .zero)

let totalFrames = Int(duration * Double(fps))
for frame in 0..<totalFrames {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
    guard let pool = adaptor.pixelBufferPool else { throw NSError(domain: "BodyModeReel", code: 3) }
    var pixelBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
          let buffer = pixelBuffer else { throw NSError(domain: "BodyModeReel", code: 4) }
    CVPixelBufferLockBaseAddress(buffer, [])
    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer),
          let context = CGContext(data: baseAddress,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
        throw NSError(domain: "BodyModeReel", code: 5)
    }
    renderFrame(context: context, time: Double(frame) / Double(fps))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    let presentationTime = CMTime(value: CMTimeValue(frame), timescale: fps)
    guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
        throw writer.error ?? NSError(domain: "BodyModeReel", code: 6)
    }
}

input.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else { throw writer.error ?? NSError(domain: "BodyModeReel", code: 7) }
try await addMusic(to: silentOutputURL, outputURL: outputURL)
try? FileManager.default.removeItem(at: silentOutputURL)
print(outputURL.path)
