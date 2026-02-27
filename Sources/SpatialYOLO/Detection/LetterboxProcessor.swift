import CoreVideo
import CoreGraphics
import CoreImage

/// Parameters for letterbox transformation and coordinate conversion.
struct LetterboxInfo {
    let scale: CGFloat
    let padX: CGFloat
    let padY: CGFloat
    let originalWidth: CGFloat
    let originalHeight: CGFloat
    let targetSize: CGFloat

    static func calculate(
        inputWidth: CGFloat,
        inputHeight: CGFloat,
        targetSize: CGFloat = 640
    ) -> LetterboxInfo {
        let scale = min(targetSize / inputWidth, targetSize / inputHeight)
        let scaledWidth = inputWidth * scale
        let scaledHeight = inputHeight * scale
        let padX = (targetSize - scaledWidth) / 2
        let padY = (targetSize - scaledHeight) / 2
        return LetterboxInfo(
            scale: scale,
            padX: padX,
            padY: padY,
            originalWidth: inputWidth,
            originalHeight: inputHeight,
            targetSize: targetSize
        )
    }

    /// Convert YOLO normalized bbox (letterbox space) to original image coordinates.
    func convertToOriginalCoordinates(_ yoloBox: CGRect) -> CGRect {
        let letterboxedX = yoloBox.minX * targetSize
        let letterboxedY = yoloBox.minY * targetSize
        let letterboxedW = yoloBox.width * targetSize
        let letterboxedH = yoloBox.height * targetSize

        let unpaddedX = letterboxedX - padX
        let unpaddedY = letterboxedY - padY

        let originalX = unpaddedX / scale
        let originalY = unpaddedY / scale
        let originalW = letterboxedW / scale
        let originalH = letterboxedH / scale

        let normalizedX = originalX / originalWidth
        let normalizedY = originalY / originalHeight
        let normalizedW = originalW / originalWidth
        let normalizedH = originalH / originalHeight

        let clampedX = max(0, min(1, normalizedX))
        let clampedY = max(0, min(1, normalizedY))
        let clampedW = max(0, min(1 - clampedX, normalizedW))
        let clampedH = max(0, min(1 - clampedY, normalizedH))

        return CGRect(x: clampedX, y: clampedY, width: clampedW, height: clampedH)
    }
}

/// Aspect-ratio-preserving preprocessor for YOLO input.
/// Rotates landscape ARKit frames to portrait and applies gray letterbox padding.
final class LetterboxProcessor {

    let targetSize: Int
    private let paddingGray: UInt8 = 114
    private var bufferPool: CVPixelBufferPool?
    private let ciContext: CIContext

    init(targetSize: Int = 640) {
        self.targetSize = targetSize
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
        setupBufferPool()
    }

    private func setupBufferPool() {
        let poolAttrs: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 2
        ]
        let bufferAttrs: [CFString: Any] = [
            kCVPixelBufferWidthKey: targetSize,
            kCVPixelBufferHeightKey: targetSize,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttrs as CFDictionary,
            bufferAttrs as CFDictionary,
            &bufferPool
        )
    }

    /// Process landscape-right ARKit frame → portrait letterboxed buffer.
    func process(_ inputBuffer: CVPixelBuffer) -> (CVPixelBuffer, LetterboxInfo)? {
        let inputWidth = CVPixelBufferGetWidth(inputBuffer)
        let inputHeight = CVPixelBufferGetHeight(inputBuffer)

        // After 90° clockwise rotation: portrait
        let rotatedWidth = CGFloat(inputHeight)
        let rotatedHeight = CGFloat(inputWidth)

        let letterboxInfo = LetterboxInfo.calculate(
            inputWidth: rotatedWidth,
            inputHeight: rotatedHeight,
            targetSize: CGFloat(targetSize)
        )

        var outputBuffer: CVPixelBuffer?
        guard let pool = bufferPool else { return nil }
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let output = outputBuffer else { return nil }

        let ciImage = CIImage(cvPixelBuffer: inputBuffer)
        let rotated = ciImage.transformed(by: CGAffineTransform(rotationAngle: -.pi / 2))
        let rotatedExtent = rotated.extent
        let translated = rotated.transformed(by: CGAffineTransform(
            translationX: -rotatedExtent.origin.x,
            y: -rotatedExtent.origin.y
        ))

        let scaleX = (CGFloat(targetSize) - 2 * letterboxInfo.padX) / rotatedWidth
        let scaleY = (CGFloat(targetSize) - 2 * letterboxInfo.padY) / rotatedHeight
        let scaled = translated.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let centered = scaled.transformed(by: CGAffineTransform(
            translationX: letterboxInfo.padX,
            y: letterboxInfo.padY
        ))

        let grayValue = CGFloat(paddingGray) / 255.0
        let grayColor = CIColor(red: grayValue, green: grayValue, blue: grayValue)
        let background = CIImage(color: grayColor).cropped(to: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))

        let composited = centered.composited(over: background)
        ciContext.render(composited, to: output)

        return (output, letterboxInfo)
    }
}
