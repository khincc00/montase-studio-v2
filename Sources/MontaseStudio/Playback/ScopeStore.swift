import AVFoundation
import CoreImage
import Observation

/// Histogram luma dari frame komposisi di playhead. Diperbarui saat diam atau setelah seek, bukan saat memutar.
@MainActor
@Observable
final class ScopeStore {
    static let binCount = 64

    var isEnabled = true {
        didSet {
            if !isEnabled { bins = [] }
        }
    }
    private(set) var bins: [Float] = []

    @ObservationIgnored private let context = CIContext(options: [.cacheIntermediates: false])
    @ObservationIgnored private var task: Task<Void, Never>?

    func refresh(output: CompositionBuilder.Output?, at time: Ticks) {
        guard isEnabled, let output else { return }
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }

            let generator = AVAssetImageGenerator(asset: output.composition)
            generator.videoComposition = output.videoComposition
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 270)
            guard let frame = try? await generator.image(at: time.cmTime).image else { return }
            guard !Task.isCancelled else { return }

            self.bins = ScopeAnalyzer.histogram(of: CIImage(cgImage: frame), context: self.context, bins: Self.binCount)
        }
    }
}

enum ScopeAnalyzer {
    /// Histogram luma ternormalisasi (0...1) memakai CIAreaHistogram.
    static func histogram(of image: CIImage, context: CIContext, bins: Int) -> [Float] {
        guard let filter = CIFilter(name: "CIAreaHistogram") else { return [] }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: "inputExtent")
        filter.setValue(bins, forKey: "inputCount")
        filter.setValue(1.0, forKey: "inputScale")
        guard let output = filter.outputImage else { return [] }

        var pixels = [Float](repeating: 0, count: bins * 4)
        pixels.withUnsafeMutableBytes { buffer in
            context.render(
                output,
                toBitmap: buffer.baseAddress!,
                rowBytes: bins * 16,
                bounds: CGRect(x: 0, y: 0, width: bins, height: 1),
                format: .RGBAf,
                colorSpace: nil
            )
        }

        var luma = (0..<bins).map { index -> Float in
            0.2126 * pixels[index * 4] + 0.7152 * pixels[index * 4 + 1] + 0.0722 * pixels[index * 4 + 2]
        }
        let peak = luma.max() ?? 0
        if peak > 0 {
            luma = luma.map { $0 / peak }
        }
        return luma
    }
}
