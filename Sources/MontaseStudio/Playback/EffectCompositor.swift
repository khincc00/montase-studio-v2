import AppKit
import AVFoundation
import CoreImage

/// Data orientasi dan transform satu klip media. `orientation` sudah dinormalisasi agar origin-nya (0,0).
struct LayerPlacement {
    let orientation: CGAffineTransform
    let naturalSize: CGSize
    let orientedSize: CGSize
    let transform: Transform
}

/// Satu lapisan untuk satu segmen waktu. Disusun dari bawah ke atas.
struct EffectLayer {
    enum Source {
        case track(CMPersistentTrackID, LayerPlacement)
        case title(CIImage)
    }

    let source: Source
    let grade: ColorGrade
    let opacity: Double
    let start: Ticks
    let end: Ticks
    let fadeIn: Ticks
    let fadeOut: Ticks

    var requiredTrackID: CMPersistentTrackID? {
        if case .track(let id, _) = source { return id }
        return nil
    }
}

/// Instruksi kustom: membawa daftar lapisan, bukan layer instruction bawaan AVFoundation.
final class EffectInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let layers: [EffectLayer]
    let canvasSize: CGSize

    /// `extraTrackIDs` mendaftarkan track yang tidak dirender tetapi wajib ada agar AVFoundation
    /// membangkitkan frame di seluruh rentang instruksi (mis. instruksi yang hanya berisi teks).
    init(timeRange: CMTimeRange, layers: [EffectLayer], canvasSize: CGSize, extraTrackIDs: [CMPersistentTrackID] = []) {
        self.timeRange = timeRange
        self.layers = layers
        self.canvasSize = canvasSize
        let ids = Set(layers.compactMap { $0.requiredTrackID } + extraTrackIDs)
        self.requiredSourceTrackIDs = ids.sorted().map { NSNumber(value: $0) }
    }
}

/// Compositor GPU berbasis Core Image. Dipakai bersama oleh preview (AVPlayer) dan export (AVAssetReader),
/// sehingga transform, crop, warna, LUT, fade, dan teks selalu identik di kedua jalur.
final class EffectCompositor: NSObject, AVVideoCompositing {
    enum CompositorError: Error {
        case setupFailed
    }

    private let renderQueue = DispatchQueue(label: "montase.compositor", qos: .userInitiated)
    private var renderContext: AVVideoCompositionRenderContext?
    /// Tanpa manajemen warna: nilai piksel sumber diteruskan apa adanya, tidak dikonversi ke working space linear.
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    private static let pixelAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
    ]

    var sourcePixelBufferAttributes: [String: Any]? { Self.pixelAttributes }
    var requiredPixelBufferAttributesForRenderContext: [String: Any] { Self.pixelAttributes }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderQueue.sync { self.renderContext = newRenderContext }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [self] in
            guard let instruction = request.videoCompositionInstruction as? EffectInstruction,
                  let context = renderContext,
                  let buffer = context.newPixelBuffer() else {
                request.finish(with: CompositorError.setupFailed)
                return
            }
            let image = Self.compose(instruction, at: request.compositionTime, request: request)
            let bounds = CGRect(origin: .zero, size: instruction.canvasSize)
            ciContext.render(image, to: buffer, bounds: bounds, colorSpace: nil)
            request.finish(withComposedVideoFrame: buffer)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}

    // MARK: - Komposisi

    static func compose(_ instruction: EffectInstruction, at time: CMTime, request: AVAsynchronousVideoCompositionRequest) -> CIImage {
        let canvas = CGRect(origin: .zero, size: instruction.canvasSize)
        let now = Ticks(seconds: time.seconds)
        var result = CIImage(color: .black).cropped(to: canvas)

        for layer in instruction.layers {
            let alpha = layer.opacity * fadeRamp(layer, at: now)
            guard alpha > 0.001, let source = sourceImage(for: layer, request: request) else { continue }

            var image = graded(source, layer.grade)
            if case .track(_, let placement) = layer.source {
                image = place(image, placement, canvas: canvas)
            }
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha)),
            ])
            result = image.composited(over: result)
        }
        return result.cropped(to: canvas)
    }

    private static func sourceImage(for layer: EffectLayer, request: AVAsynchronousVideoCompositionRequest) -> CIImage? {
        switch layer.source {
        case .track(let id, _):
            guard let buffer = request.sourceFrame(byTrackID: id) else { return nil }
            // Tanpa konversi color space: nilai piksel diteruskan apa adanya, seperti pemutar AVFoundation.
            return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        case .title(let image):
            return image
        }
    }

    /// Fade masuk dan keluar sebagai pengali opacity. Dissolve di awal clip memakai fade masuk di atas lapisan bawahnya.
    static func fadeRamp(_ layer: EffectLayer, at time: Ticks) -> Double {
        var ramp = 1.0
        if layer.fadeIn > .zero {
            ramp *= min(max((time - layer.start).seconds / layer.fadeIn.seconds, 0), 1)
        }
        if layer.fadeOut > .zero {
            ramp *= min(max((layer.end - time).seconds / layer.fadeOut.seconds, 0), 1)
        }
        return ramp
    }

    // MARK: - Geometri

    /// Menerapkan orientasi file, crop, lalu skala aspect-fit, rotasi, dan posisi ke kanvas.
    /// Seluruh langkah dilakukan di ruang Core Image (origin kiri bawah) setelah dipetakan dari ruang orientasi.
    static func place(_ input: CIImage, _ placement: LayerPlacement, canvas: CGRect) -> CIImage {
        var image = input
        let natural = placement.naturalSize
        // Buffer bisa lebih kecil dari ukuran natural (preview kualitas rendah); samakan dulu.
        if natural.width > 0, image.extent.width > 0 {
            let k = natural.width / image.extent.width
            if abs(k - 1) > 0.001 {
                image = image.transformed(by: CGAffineTransform(scaleX: k, y: k))
            }
        }

        let ow = placement.orientedSize.width
        let oh = placement.orientedSize.height
        guard ow > 0, oh > 0 else { return input }

        // 1) Buffer (TL, natural) → orientasi tampilan (TL) → Core Image.
        let sourceHeight = natural.height
        let toTopLeft = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: sourceHeight)
        let toCoreImage = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: oh)
        let oriented = image.transformed(by: toTopLeft.concatenating(placement.orientation).concatenating(toCoreImage))

        // 2) Crop dalam ruang orientasi.
        let t = placement.transform
        let cropRect = CGRect(
            x: CGFloat(t.cropLeft) * ow,
            y: CGFloat(t.cropBottom) * oh,
            width: ow * CGFloat(1 - t.cropLeft - t.cropRight),
            height: oh * CGFloat(1 - t.cropTop - t.cropBottom)
        )
        guard cropRect.width > 1, cropRect.height > 1 else { return input }
        let cropped = oriented.cropped(to: cropRect)

        // 3) Aspect-fit, skala pengguna, rotasi (positif = searah jarum jam), lalu posisi.
        let fit = min(canvas.width / cropRect.width, canvas.height / cropRect.height) * CGFloat(t.scale)
        let matrix = CGAffineTransform(translationX: -cropped.extent.midX, y: -cropped.extent.midY)
            .concatenating(CGAffineTransform(scaleX: fit, y: fit))
            .concatenating(CGAffineTransform(rotationAngle: -CGFloat(t.rotation) * .pi / 180))
            .concatenating(CGAffineTransform(
                translationX: canvas.midX + CGFloat(t.offsetX),
                y: canvas.midY - CGFloat(t.offsetY)
            ))
        return cropped.transformed(by: matrix)
    }

    // MARK: - Warna

    static func graded(_ input: CIImage, _ g: ColorGrade) -> CIImage {
        var image = input
        if g.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: g.exposure])
        }
        if g.highlights != 0 || g.shadows != 0 {
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 1 - g.highlights,
                "inputShadowAmount": g.shadows,
            ])
        }
        if g.contrast != 1 || g.saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: g.contrast,
                kCIInputSaturationKey: g.saturation,
            ])
        }
        if g.temperature != 6500 || g.tint != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: g.temperature, y: g.tint),
            ])
        }
        if let path = g.lutPath, g.lutIntensity > 0, let lut = LUTCache.shared.lut(at: path),
           let cube = CIFilter(name: "CIColorCube") {
            cube.setValue(lut.dimension, forKey: "inputCubeDimension")
            cube.setValue(lut.data, forKey: "inputCubeData")
            cube.setValue(image, forKey: kCIInputImageKey)
            if let looked = cube.outputImage {
                if g.lutIntensity >= 1 {
                    image = looked
                } else if let mix = CIFilter(name: "CIDissolveTransition") {
                    mix.setValue(looked, forKey: kCIInputImageKey)
                    mix.setValue(image, forKey: kCIInputTargetImageKey)
                    mix.setValue(1 - g.lutIntensity, forKey: kCIInputTimeKey)
                    image = mix.outputImage ?? image
                }
            }
        }
        return image
    }
}

/// Merender teks menjadi gambar sebesar kanvas. Dipanggil saat menyusun komposisi.
enum TitleRenderer {
    static func image(for style: TitleStyle, canvas: CGSize) -> CIImage {
        let width = max(Int(canvas.width), 1)
        let height = max(Int(canvas.height), 1)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CIImage.empty()
        }

        let size = CGFloat(style.fontSize)
        let font = NSFont(name: style.fontName, size: size) ?? NSFont.boldSystemFont(ofSize: size)
        let color = NSColor(
            red: CGFloat((style.colorHex >> 16) & 0xFF) / 255,
            green: CGFloat((style.colorHex >> 8) & 0xFF) / 255,
            blue: CGFloat(style.colorHex & 0xFF) / 255,
            alpha: 1
        )
        let text = NSAttributedString(string: style.text, attributes: [.font: font, .foregroundColor: color])
        let textSize = text.size()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let centerY = CGFloat(height) * (1 - CGFloat(style.positionY))
        text.draw(at: NSPoint(x: (CGFloat(width) - textSize.width) / 2, y: centerY - textSize.height / 2))
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else { return CIImage.empty() }
        return CIImage(cgImage: cgImage)
    }
}
