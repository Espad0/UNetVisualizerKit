import CoreML
import Vision
import CoreImage
import Accelerate

/// Protocol defining the interface for U-Net model predictions
public protocol UNetModelProtocol {
    /// Input image dimensions expected by the model
    var inputSize: CGSize { get }
    
    /// Number of output channels in the prediction
    var outputChannels: Int { get }
    
    /// Perform prediction on the given image
    func predict(_ image: CGImage) async throws -> UNetPrediction
}

/// Wrapper for Core ML U-Net models with optimized performance
public final class UNetModel: UNetModelProtocol {
    
    /// Errors that can occur during model operations
    public enum ModelError: LocalizedError {
        case invalidModelURL
        case modelLoadingFailed(Error)
        case inputPreprocessingFailed
        case predictionFailed(Error)
        case outputProcessingFailed
        
        public var errorDescription: String? {
            switch self {
            case .invalidModelURL:
                return "Invalid model URL provided"
            case .modelLoadingFailed(let error):
                return "Failed to load model: \(error.localizedDescription)"
            case .inputPreprocessingFailed:
                return "Failed to preprocess input image"
            case .predictionFailed(let error):
                return "Prediction failed: \(error.localizedDescription)"
            case .outputProcessingFailed:
                return "Failed to process model output"
            }
        }
    }
    
    private let model: MLModel
    private let visionModel: VNCoreMLModel
    
    public let inputSize: CGSize
    public let outputChannels: Int
    
    /// Configuration for model processing
    public struct Configuration {
        /// Whether to use GPU acceleration
        public var preferGPU: Bool = true
        
        /// Maximum number of concurrent predictions
        public var maxConcurrentPredictions: Int = 2
        
        /// Input normalization parameters
        public var normalizationMean: Float = 0.5
        public var normalizationStd: Float = 0.5
        
        public init() {}
    }
    
    private var configuration: Configuration
    
    /// Initialize with a Core ML model URL
    public init(modelURL: URL, configuration: Configuration = Configuration()) throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw ModelError.invalidModelURL
        }
        
        self.configuration = configuration
        
        do {
            // Configure model for optimal performance
            let config = MLModelConfiguration()
            config.computeUnits = configuration.preferGPU ? .all : .cpuOnly
            
            self.model = try MLModel(contentsOf: modelURL, configuration: config)
            self.visionModel = try VNCoreMLModel(for: model)
            
            // Extract model metadata
            guard let inputDescription = model.modelDescription.inputDescriptionsByName.values.first,
                  let inputConstraint = inputDescription.imageConstraint else {
                throw ModelError.modelLoadingFailed(NSError(domain: "UNetModel", code: -1))
            }
            
            self.inputSize = CGSize(
                width: inputConstraint.pixelsWide,
                height: inputConstraint.pixelsHigh
            )
            
            // Determine output channels from model description
            if let outputDescription = model.modelDescription.outputDescriptionsByName.values.first,
               let multiArrayConstraint = outputDescription.multiArrayConstraint {
                self.outputChannels = multiArrayConstraint.shape[3].intValue
            } else {
                self.outputChannels = 1 // Default for single-channel output
            }
            
        } catch {
            throw ModelError.modelLoadingFailed(error)
        }
    }
    
    /// Perform prediction on the given image
    public func predict(_ image: CGImage) async throws -> UNetPrediction {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Create Vision request
        let request = VNCoreMLRequest(model: visionModel) { request, error in
            if let error = error {
                print("Vision request error: \(error)")
            }
        }
        
        // Configure request
        request.imageCropAndScaleOption = .scaleFill
        
        // Perform prediction
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let firstResult = results.first,
                  let multiArray = firstResult.featureValue.multiArrayValue else {
                throw ModelError.outputProcessingFailed
            }
            
            let inferenceTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // Convert to ms
            
            // Process output into prediction
            let prediction = try processOutput(multiArray, inferenceTime: inferenceTime)
            return prediction
            
        } catch {
            throw ModelError.predictionFailed(error)
        }
    }
    
    /// Process model output into structured prediction
    private func processOutput(_ multiArray: MLMultiArray, inferenceTime: Double) throws -> UNetPrediction {
        // Extract dimensions
        let shape = multiArray.shape
        guard shape.count >= 4 else {
            throw ModelError.outputProcessingFailed
        }
        
        let height = shape[1].intValue
        let width = shape[2].intValue
        let channels = shape[3].intValue
        
        // Convert MLMultiArray to channel arrays
        var channelData: [ChannelData] = []
        
        for channelIndex in 0..<channels {
            var values: [Float] = []
            var minValue: Float = .infinity
            var maxValue: Float = -.infinity
            
            // Extract channel data
            for y in 0..<height {
                for x in 0..<width {
                    let indices = [0, y, x, channelIndex] as [NSNumber]
                    let value = multiArray[indices].floatValue
                    values.append(value)
                    minValue = min(minValue, value)
                    maxValue = max(maxValue, value)
                }
            }
            
            let channel = ChannelData(
                index: channelIndex,
                values: values,
                width: width,
                height: height,
                minValue: minValue,
                maxValue: maxValue
            )
            channelData.append(channel)
        }
        
        return UNetPrediction(
            channels: channelData,
            inferenceTime: inferenceTime,
            timestamp: Date()
        )
    }
}

/// Represents the output of a U-Net prediction
public struct UNetPrediction {
    /// Individual channel predictions
    public let channels: [ChannelData]
    
    /// Inference time in milliseconds
    public let inferenceTime: Double
    
    /// Timestamp of the prediction
    public let timestamp: Date
    
    /// Get a specific channel by index
    public func channel(_ index: Int) -> ChannelData? {
        guard index >= 0 && index < channels.count else { return nil }
        return channels[index]
    }
    
    /// Compute aggregate prediction (e.g., argmax across channels)
    public func aggregatePrediction() -> [Float] {
        guard let firstChannel = channels.first else { return [] }
        
        let pixelCount = firstChannel.values.count
        var result = Array<Float>(repeating: 0, count: pixelCount)
        
        for pixelIndex in 0..<pixelCount {
            var maxValue: Float = -.infinity
            var maxChannel = 0
            
            for (channelIndex, channel) in channels.enumerated() {
                let value = channel.values[pixelIndex]
                if value > maxValue {
                    maxValue = value
                    maxChannel = channelIndex
                }
            }
            
            result[pixelIndex] = Float(maxChannel)
        }
        
        return result
    }
}

/// Represents data for a single output channel
public struct ChannelData {
    /// Channel index
    public let index: Int
    
    /// Raw prediction values
    public let values: [Float]
    
    /// Dimensions
    public let width: Int
    public let height: Int
    
    /// Statistics
    public let minValue: Float
    public let maxValue: Float
    
    /// Normalized values (0-1 range)
    public var normalizedValues: [Float] {
        let range = maxValue - minValue
        guard range > 0 else { return values }
        
        return values.map { ($0 - minValue) / range }
    }
    
    /// Convert to CGImage for visualization
    public func toCGImage(colorMap: ColorMap = .grayscale) -> CGImage? {
        let normalized = normalizedValues
        var pixelData = [UInt8]()
        
        for value in normalized {
            let color = colorMap.color(for: value)
            pixelData.append(color.r)
            pixelData.append(color.g)
            pixelData.append(color.b)
            pixelData.append(255) // Alpha
        }
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let providerRef = CGDataProvider(data: NSData(bytes: pixelData, length: pixelData.count)) else {
            return nil
        }
        
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: rgbColorSpace,
            bitmapInfo: bitmapInfo,
            provider: providerRef,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}