import CoreML
import Vision
import CoreImage
import Accelerate

/// Errors that can occur during model operations
public enum UNetModelError: LocalizedError {
    case modelLoadingFailed
    case predictionFailed(Error)
    case outputProcessingFailed
    
    public var errorDescription: String? {
        switch self {
        case .modelLoadingFailed:
            return "Failed to load the UNet model"
        case .predictionFailed(let error):
            return "Prediction failed: \(error.localizedDescription)"
        case .outputProcessingFailed:
            return "Failed to process model output"
        }
    }
}

/// Handler for Core ML U-Net model with simplified interface
public class UNetModelHandler {
    private let model: MLModel
    
    /// Model input size
    public var inputSize: CGSize {
        guard let inputDescription = model.modelDescription.inputDescriptionsByName.values.first,
              let multiArrayConstraint = inputDescription.multiArrayConstraint else {
            return CGSize(width: 512, height: 512) // Default size
        }
        
        let shape = multiArrayConstraint.shape
        if shape.count >= 3 {
            let height = shape[shape.count - 3].intValue
            let width = shape[shape.count - 2].intValue
            return CGSize(width: width, height: height)
        }
        
        return CGSize(width: 512, height: 512) // Default size
    }
    
    /// Model output channels
    public var outputChannels: Int {
        guard let outputDescription = model.modelDescription.outputDescriptionsByName.values.first,
              let multiArrayConstraint = outputDescription.multiArrayConstraint else {
            return 1 // Default channel count
        }
        
        let shape = multiArrayConstraint.shape
        if shape.count >= 1 {
            return shape.last?.intValue ?? 1
        }
        
        return 1 // Default channel count
    }
    
    public init(modelName: String, bundle: Bundle = .main) throws {
        // Load model from bundle
        guard let modelURL = bundle.url(forResource: modelName, withExtension: "mlmodelc") else {
            print("Model file '\(modelName).mlmodelc' not found in bundle.")
            throw UNetModelError.modelLoadingFailed
        }
        
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            self.model = try MLModel(contentsOf: modelURL, configuration: config)
        } catch {
            print("Failed to load the UNet model: \(error)")
            throw UNetModelError.modelLoadingFailed
        }
    }
    
    /// Initialize with a pre-compiled MLModel instance
    /// This enables compile-time model loading when you have a generated model class
    /// Usage: let handler = try UNetModelHandler(compiledModel: YourModel(configuration: .init()))
    public init(compiledModel: MLModel) {
        self.model = compiledModel
    }
    
    /// Initialize with a specific model URL
    public init(modelURL: URL) throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            print("Model file not found at: \(modelURL.path)")
            throw UNetModelError.modelLoadingFailed
        }
        
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            self.model = try MLModel(contentsOf: modelURL, configuration: config)
        } catch {
            print("Failed to load model: \(error)")
            throw UNetModelError.modelLoadingFailed
        }
    }
    
    /// Initialize with an MLModel directly (deprecated, use init(compiledModel:) instead)
    @available(*, deprecated, renamed: "init(compiledModel:)")
    public init(model: MLModel) {
        self.model = model
    }
    
    /// Performs prediction on the given MLMultiArray
    /// - Parameter multiArray: The input MLMultiArray
    /// - Returns: The predicted MLMultiArray or nil if prediction fails
    public func predict(multiArray: MLMultiArray) -> MLMultiArray? {
        do {
            // Get the first input key from the model
            guard let inputKey = model.modelDescription.inputDescriptionsByName.keys.first else {
                print("No input key found in model")
                return nil
            }
            
            // Create MLShapedArray from MLMultiArray
            let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inputKey: MLFeatureValue(multiArray: multiArray)]))
            
            // Get the first output key from the model
            guard let outputKey = model.modelDescription.outputDescriptionsByName.keys.first,
                  let outputFeature = prediction.featureValue(for: outputKey),
                  let outputMultiArray = outputFeature.multiArrayValue else {
                print("Failed to extract output from prediction")
                return nil
            }
            
            return outputMultiArray
        } catch {
            print("Prediction failed with error: \(error)")
            return nil
        }
    }
    
    /// Performs prediction on a CGImage
    /// - Parameter image: The input CGImage
    /// - Returns: UNetPrediction with processed results
    /// - Throws: UNetModelError if prediction fails
    public func predict(image: CGImage) async throws -> UNetPrediction {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Convert CGImage to MLMultiArray
                guard let multiArray = self.convertImageToMultiArray(image) else {
                    continuation.resume(throwing: UNetModelError.outputProcessingFailed)
                    return
                }
                
                // Perform prediction
                guard let outputArray = self.predict(multiArray: multiArray) else {
                    continuation.resume(throwing: UNetModelError.predictionFailed(NSError(domain: "UNetModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Prediction returned nil"])))
                    return
                }
                
                // Process output into UNetPrediction
                guard let prediction = self.processOutput(outputArray) else {
                    continuation.resume(throwing: UNetModelError.outputProcessingFailed)
                    return
                }
                
                continuation.resume(returning: prediction)
            }
        }
    }
    
    /// Synchronous version of predict for backward compatibility
    /// - Parameter image: The input CGImage
    /// - Returns: UNetPrediction with processed results or nil if prediction fails
    public func predictSync(image: CGImage) -> UNetPrediction? {
        // Convert CGImage to MLMultiArray
        guard let multiArray = convertImageToMultiArray(image) else {
            print("Failed to convert image to MLMultiArray")
            return nil
        }
        
        // Perform prediction
        guard let outputArray = predict(multiArray: multiArray) else {
            return nil
        }
        
        // Process output into UNetPrediction
        return processOutput(outputArray)
    }
    
    /// Convert CGImage to MLMultiArray
    private func convertImageToMultiArray(_ image: CGImage) -> MLMultiArray? {
        // Get model's expected input size
        let expectedWidth = Int(inputSize.width)
        let expectedHeight = Int(inputSize.height)
        
        // Resize image if needed
        let resizedImage: CGImage
        if image.width != expectedWidth || image.height != expectedHeight {
            guard let resized = resizeImage(image, to: CGSize(width: expectedWidth, height: expectedHeight)) else {
                print("Failed to resize image to expected dimensions: \(expectedWidth)x\(expectedHeight)")
                return nil
            }
            resizedImage = resized
        } else {
            resizedImage = image
        }
        
        // Create MLMultiArray with expected shape [1, height, width, 3] for RGB
        guard let multiArray = try? MLMultiArray(shape: [1, NSNumber(value: expectedHeight), NSNumber(value: expectedWidth), 3], dataType: .float32) else {
            return nil
        }
        
        // Convert image to pixel data
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: expectedWidth, height: expectedHeight, bitsPerComponent: 8, bytesPerRow: expectedWidth * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        
        context.draw(resizedImage, in: CGRect(x: 0, y: 0, width: expectedWidth, height: expectedHeight))
        
        guard let pixelData = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }
        
        // Fill MLMultiArray
        for y in 0..<expectedHeight {
            for x in 0..<expectedWidth {
                let pixelIndex = (y * expectedWidth + x) * 4
                let r = Float(pixelData[pixelIndex]) / 255.0
                let g = Float(pixelData[pixelIndex + 1]) / 255.0
                let b = Float(pixelData[pixelIndex + 2]) / 255.0
                
                multiArray[[0, NSNumber(value: y), NSNumber(value: x), 0]] = NSNumber(value: r)
                multiArray[[0, NSNumber(value: y), NSNumber(value: x), 1]] = NSNumber(value: g)
                multiArray[[0, NSNumber(value: y), NSNumber(value: x), 2]] = NSNumber(value: b)
            }
        }
        
        return multiArray
    }
    
    /// Resize a CGImage to the specified size
    private func resizeImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return context.makeImage()
    }
    
    /// Process model output into structured prediction
    private func processOutput(_ multiArray: MLMultiArray) -> UNetPrediction? {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Extract dimensions
        let shape = multiArray.shape
        guard shape.count >= 4 else {
            print("Invalid output shape")
            return nil
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
        
        let inferenceTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
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