import CoreML
import Vision
import CoreVideo
import CoreImage
import Foundation
import QuartzCore

/// Built-in YOLO detector using Vision/CoreML.
/// Supports models with built-in NMS (e.g., exported from Ultralytics).
public final class YOLODetector: ObjectDetector, @unchecked Sendable {

    // MARK: - Properties

    private let modelName: String
    private var detector: VNCoreMLModel?
    private var visionRequest: VNCoreMLRequest?
    private var isLoaded = false
    private var inputSize: CGSize = CGSize(width: 640, height: 640)
    private var letterboxProcessor: LetterboxProcessor?

    /// End-to-end model support (e.g., YOLO26 with built-in NMS)
    private var isEndToEnd = false
    private var rawMLModel: MLModel?
    private var e2eInputName: String?

    public var confidenceThreshold: Float
    public var iouThreshold: Float
    public var maxDetections: Int

    // MARK: - Init

    /// Initialize with a model name to look up in the app bundle.
    /// - Parameters:
    ///   - modelName: Name of the .mlmodelc or .mlpackage resource (without extension)
    ///   - confidenceThreshold: Minimum detection confidence
    ///   - iouThreshold: IoU threshold for NMS
    ///   - maxDetections: Maximum number of detections per frame
    public init(
        modelName: String = "yolo",
        confidenceThreshold: Float = 0.35,
        iouThreshold: Float = 0.45,
        maxDetections: Int = 50
    ) {
        self.modelName = modelName
        self.confidenceThreshold = confidenceThreshold
        self.iouThreshold = iouThreshold
        self.maxDetections = maxDetections
        self.letterboxProcessor = LetterboxProcessor(targetSize: 640)
    }

    // MARK: - Model Loading

    public func loadModel() async throws {
        guard !isLoaded else { return }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: YOLODetectorError.serviceNotAvailable)
                    return
                }
                do {
                    guard let modelURL = Bundle.main.url(forResource: self.modelName, withExtension: "mlmodelc")
                            ?? Bundle.main.url(forResource: self.modelName, withExtension: "mlpackage") else {
                        throw YOLODetectorError.modelNotFound(self.modelName)
                    }

                    let config = MLModelConfiguration()
                    config.computeUnits = .all

                    let mlModel: MLModel
                    if modelURL.pathExtension == "mlmodelc" {
                        mlModel = try MLModel(contentsOf: modelURL, configuration: config)
                    } else {
                        let compiledURL = try MLModel.compileModel(at: modelURL)
                        mlModel = try MLModel(contentsOf: compiledURL, configuration: config)
                    }

                    // Determine model input size from image input
                    let inputDescriptions = mlModel.modelDescription.inputDescriptionsByName
                    var imageInputName: String?
                    for (name, desc) in inputDescriptions {
                        if let constraint = desc.imageConstraint {
                            self.inputSize = CGSize(
                                width: CGFloat(constraint.pixelsWide),
                                height: CGFloat(constraint.pixelsHigh)
                            )
                            imageInputName = name
                            break
                        }
                    }

                    // Auto-detect: standard models accept iouThreshold/confidenceThreshold inputs
                    let hasThresholdInputs = inputDescriptions["iouThreshold"] != nil
                        && inputDescriptions["confidenceThreshold"] != nil

                    if hasThresholdInputs {
                        // Standard model — use Vision framework path
                        let coreMLModel = try VNCoreMLModel(for: mlModel)
                        coreMLModel.featureProvider = ThresholdProvider(
                            iouThreshold: Double(self.iouThreshold),
                            confidenceThreshold: Double(self.confidenceThreshold)
                        )
                        self.detector = coreMLModel
                        self.visionRequest = VNCoreMLRequest(model: coreMLModel) { _, _ in }
                        self.visionRequest?.imageCropAndScaleOption = .scaleFill
                        self.isEndToEnd = false
                    } else {
                        // End-to-end model (e.g., YOLO26) — use direct MLModel prediction
                        self.rawMLModel = mlModel
                        self.e2eInputName = imageInputName
                        self.isEndToEnd = true
                    }

                    self.letterboxProcessor = LetterboxProcessor(targetSize: Int(self.inputSize.width))
                    self.isLoaded = true

                    DispatchQueue.main.async {
                        continuation.resume()
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: - Detection

    public func detect(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> [Detection2D] {
        guard isLoaded else { return [] }

        if isEndToEnd {
            return detectEndToEnd(pixelBuffer: pixelBuffer, timestamp: timestamp)
        } else {
            return detectStandard(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }

    // MARK: - Standard Vision-Based Detection

    private func detectStandard(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> [Detection2D] {
        guard let request = visionRequest else { return [] }

        return autoreleasepool {
            if let processor = letterboxProcessor,
               let (letterboxedBuffer, letterboxInfo) = processor.process(pixelBuffer) {
                let handler = VNImageRequestHandler(cvPixelBuffer: letterboxedBuffer, orientation: .up, options: [:])
                do {
                    try handler.perform([request])
                    return processResults(request.results, timestamp: timestamp, letterboxInfo: letterboxInfo)
                } catch {
                    return []
                }
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
            do {
                try handler.perform([request])
                return processResults(request.results, timestamp: timestamp, letterboxInfo: nil)
            } catch {
                return []
            }
        }
    }

    // MARK: - End-to-End Direct Prediction

    private func detectEndToEnd(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> [Detection2D] {
        guard let model = rawMLModel, let inputName = e2eInputName else { return [] }

        return autoreleasepool {
            guard let processor = letterboxProcessor,
                  let (letterboxedBuffer, letterboxInfo) = processor.process(pixelBuffer) else {
                return []
            }

            do {
                let inputSize = Int(self.inputSize.width)
                let imageConstraint = model.modelDescription.inputDescriptionsByName[inputName]?.imageConstraint
                let featureValue: MLFeatureValue
                if let constraint = imageConstraint {
                    featureValue = try MLFeatureValue(
                        cgImage: createCGImage(from: letterboxedBuffer),
                        constraint: constraint
                    )
                } else {
                    featureValue = try MLFeatureValue(
                        cgImage: createCGImage(from: letterboxedBuffer),
                        pixelsWide: inputSize,
                        pixelsHigh: inputSize,
                        pixelFormatType: kCVPixelFormatType_32BGRA
                    )
                }

                let inputProvider = try MLDictionaryFeatureProvider(
                    dictionary: [inputName: featureValue]
                )
                let output = try model.prediction(from: inputProvider)

                return parseEndToEndOutput(output, letterboxInfo: letterboxInfo)
            } catch {
                return []
            }
        }
    }

    /// Parse end-to-end output MLMultiArray shape [1, 300, 6]:
    /// Each detection: [x1, y1, x2, y2, confidence, class_id]
    private func parseEndToEndOutput(
        _ output: MLFeatureProvider,
        letterboxInfo: LetterboxInfo
    ) -> [Detection2D] {
        // Find the output MLMultiArray
        guard let outputName = output.featureNames.first,
              let multiArray = output.featureValue(for: outputName)?.multiArrayValue else {
            return []
        }

        let shape = multiArray.shape.map { $0.intValue }
        // Expected shape: [1, N, 6] where N is max detections (typically 300)
        guard shape.count == 3, shape[2] >= 6 else { return [] }

        let numDetections = shape[1]
        let stride0 = multiArray.strides[0].intValue
        let stride1 = multiArray.strides[1].intValue
        let stride2 = multiArray.strides[2].intValue
        let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: stride0)
        let inputDim = Float(self.inputSize.width)

        var detections: [Detection2D] = []

        for i in 0..<numDetections {
            let base = i * stride1
            let conf = ptr[base + 4 * stride2]
            guard conf >= confidenceThreshold else { continue }

            let x1 = CGFloat(ptr[base + 0 * stride2] / inputDim)
            let y1 = CGFloat(ptr[base + 1 * stride2] / inputDim)
            let x2 = CGFloat(ptr[base + 2 * stride2] / inputDim)
            let y2 = CGFloat(ptr[base + 3 * stride2] / inputDim)
            let classId = Int(ptr[base + 5 * stride2])

            let letterboxBox = CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
            let normalizedBox = letterboxInfo.convertToOriginalCoordinates(letterboxBox)

            if normalizedBox.width < 0.01 || normalizedBox.height < 0.01 {
                continue
            }

            let label = COCOLabels.label(for: classId)
            detections.append(Detection2D(
                boundingBox: normalizedBox,
                classLabel: label,
                confidence: conf
            ))

            if detections.count >= maxDetections { break }
        }

        return detections
    }

    /// Create a CGImage from a CVPixelBuffer for MLFeatureValue input.
    private func createCGImage(from buffer: CVPixelBuffer) -> CGImage {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)!
    }

    // MARK: - Result Processing

    private func processResults(
        _ results: [VNObservation]?,
        timestamp: TimeInterval,
        letterboxInfo: LetterboxInfo?
    ) -> [Detection2D] {
        guard let observations = results as? [VNRecognizedObjectObservation] else { return [] }

        var detections: [Detection2D] = []

        for observation in observations.prefix(maxDetections) {
            // Vision uses bottom-left origin → convert to top-left
            let bbox = observation.boundingBox
            let flippedBox = CGRect(
                x: bbox.minX,
                y: 1 - bbox.maxY,
                width: bbox.width,
                height: bbox.height
            )

            // Convert from letterbox coordinates to original image coordinates
            let normalizedBox: CGRect
            if let info = letterboxInfo {
                normalizedBox = info.convertToOriginalCoordinates(flippedBox)
            } else {
                normalizedBox = flippedBox
            }

            if normalizedBox.width < 0.01 || normalizedBox.height < 0.01 {
                continue
            }

            let confidence = observation.labels.first?.confidence ?? observation.confidence
            let label = observation.labels.first?.identifier ?? "object"

            if confidence >= confidenceThreshold {
                detections.append(Detection2D(
                    boundingBox: normalizedBox,
                    classLabel: label,
                    confidence: confidence
                ))
            }
        }

        return detections
    }
}

// MARK: - Threshold Provider

private class ThresholdProvider: MLFeatureProvider {
    let iouThreshold: Double
    let confidenceThreshold: Double

    var featureNames: Set<String> {
        ["iouThreshold", "confidenceThreshold"]
    }

    init(iouThreshold: Double = 0.45, confidenceThreshold: Double = 0.25) {
        self.iouThreshold = iouThreshold
        self.confidenceThreshold = confidenceThreshold
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "iouThreshold":
            return MLFeatureValue(double: iouThreshold)
        case "confidenceThreshold":
            return MLFeatureValue(double: confidenceThreshold)
        default:
            return nil
        }
    }
}

// MARK: - Errors

public enum YOLODetectorError: LocalizedError {
    case modelNotFound(String)
    case serviceNotAvailable

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "YOLO model '\(name)' (.mlmodelc/.mlpackage) not found in bundle"
        case .serviceNotAvailable:
            return "YOLO detector service not available"
        }
    }
}
