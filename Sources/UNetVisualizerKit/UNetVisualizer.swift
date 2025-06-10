import Foundation
import CoreML
import Vision
import CoreImage
import Combine
import AsyncAlgorithms

/// Main class for visualizing U-Net predictions with performance monitoring
@MainActor
public final class UNetVisualizer: ObservableObject {
    
    /// Configuration for the visualizer
    public struct Configuration {
        /// Visualization mode for channels
        public var channelVisualization: ChannelVisualizationMode = .heatmap
        
        /// Whether to show performance overlay
        public var showPerformanceOverlay: Bool = true
        
        /// Target frames per second
        public var targetFPS: Int = 30
        
        /// Color map for visualization
        public var colorMap: ColorMap = .viridis
        
        /// Alpha blending for overlay mode
        public var overlayAlpha: Float = 0.5
        
        /// Whether to cache processed images
        public var enableCaching: Bool = true
        
        /// Maximum cache size in MB
        public var maxCacheSize: Int = 100
        
        public init() {}
    }
    
    /// Visualization modes for channels
    public enum ChannelVisualizationMode {
        case heatmap
        case overlay
        case sideBySide
        case grid
        case animated
    }
    
    /// Published properties for SwiftUI integration
    @Published public private(set) var isProcessing: Bool = false
    @Published public private(set) var currentFPS: Double = 0
    @Published public private(set) var averageInferenceTime: Double = 0
    @Published public private(set) var lastPrediction: UNetPrediction?
    @Published public private(set) var visualizationImage: CGImage?
    
    private let model: UNetModelHandler
    private var configuration: Configuration
    private let performanceMonitor: PerformanceMonitor
    private let imageCache = ImageCache()
    
    /// Processing queue for background operations
    private let processingQueue = DispatchQueue(
        label: "com.unetvisualizer.processing",
        qos: .userInitiated,
        attributes: .concurrent
    )
    
    /// Combine cancellables
    private var cancellables = Set<AnyCancellable>()
    
    /// Initialize with an MLModel
    public init(model: MLModel, configuration: Configuration = Configuration()) throws {
        self.model = UNetModelHandler(compiledModel: model)
        self.configuration = configuration
        self.performanceMonitor = PerformanceMonitor()
        
        setupBindings()
    }
    
    /// Initialize with a UNetModelHandler
    public init(modelHandler: UNetModelHandler, configuration: Configuration = Configuration()) {
        self.model = modelHandler
        self.configuration = configuration
        self.performanceMonitor = PerformanceMonitor()
        
        setupBindings()
    }
    
    /// Configure the visualizer
    public func configure(_ block: (inout Configuration) -> Void) {
        block(&configuration)
        imageCache.maxSize = configuration.maxCacheSize * 1024 * 1024 // Convert to bytes
    }
    
    /// Get the current configuration
    public var currentConfiguration: Configuration {
        return configuration
    }
    
    /// Get the model input size
    public var modelInputSize: CGSize {
        return model.inputSize
    }
    
    /// Get the model output channels
    public var modelOutputChannels: Int {
        return model.outputChannels
    }
    
    /// Process a single image
    public func process(_ image: CGImage) async throws -> VisualizationResult {
        isProcessing = true
        defer { isProcessing = false }
        
        // Check cache if enabled
        if configuration.enableCaching,
           let cacheKey = image.cacheKey,
           let cachedResult = imageCache.get(key: cacheKey) {
            return cachedResult
        }
        
        // Perform prediction
        let prediction = try await model.predict(image: image)
        lastPrediction = prediction
        
        // Update performance metrics
        performanceMonitor.recordInference(time: prediction.inferenceTime)
        averageInferenceTime = performanceMonitor.averageInferenceTime
        currentFPS = performanceMonitor.currentFPS
        
        // Generate visualization
        let visualization = try await generateVisualization(
            from: prediction,
            originalImage: image
        )
        
        visualizationImage = visualization
        
        let result = VisualizationResult(
            prediction: prediction,
            visualizedImage: visualization,
            performanceMetrics: performanceMonitor.currentMetrics()
        )
        
        // Cache result if enabled
        if configuration.enableCaching, let cacheKey = image.cacheKey {
            imageCache.set(key: cacheKey, value: result)
        }
        
        return result
    }
    
    /// Process a stream of images
    public func processStream(_ images: AsyncStream<CGImage>) async throws {
        for await image in images {
            do {
                _ = try await process(image)
            } catch {
                print("Error processing image: \(error)")
            }
            
            // Rate limiting based on target FPS
            let targetFrameTime = 1.0 / Double(configuration.targetFPS)
            try await Task.sleep(nanoseconds: UInt64(targetFrameTime * 1_000_000_000))
        }
    }
    
    /// Generate visualization based on mode
    private func generateVisualization(
        from prediction: UNetPrediction,
        originalImage: CGImage
    ) async throws -> CGImage {
        switch configuration.channelVisualization {
        case .heatmap:
            return try generateHeatmapVisualization(prediction: prediction)
            
        case .overlay:
            return try generateOverlayVisualization(
                prediction: prediction,
                originalImage: originalImage
            )
            
        case .sideBySide:
            return try generateSideBySideVisualization(
                prediction: prediction,
                originalImage: originalImage
            )
            
        case .grid:
            return try generateGridVisualization(prediction: prediction)
            
        case .animated:
            return try generateAnimatedVisualization(prediction: prediction)
        }
    }
    
    /// Generate heatmap visualization
    private func generateHeatmapVisualization(prediction: UNetPrediction) throws -> CGImage {
        // For single channel, visualize directly
        if prediction.channels.count == 1,
           let channel = prediction.channels.first,
           let image = channel.toCGImage(colorMap: configuration.colorMap) {
            return image
        }
        
        // For multiple channels, show aggregate
        let aggregated = prediction.aggregatePrediction()
        let width = prediction.channels[0].width
        let height = prediction.channels[0].height
        
        // Normalize aggregated values
        let maxValue = Float(prediction.channels.count - 1)
        let normalized = aggregated.map { $0 / maxValue }
        
        // Create channel data for visualization
        let channelData = ChannelData(
            index: 0,
            values: normalized,
            width: width,
            height: height,
            minValue: 0,
            maxValue: 1
        )
        
        guard let image = channelData.toCGImage(colorMap: configuration.colorMap) else {
            throw VisualizationError.imageGenerationFailed
        }
        
        return image
    }
    
    /// Generate overlay visualization
    private func generateOverlayVisualization(
        prediction: UNetPrediction,
        originalImage: CGImage
    ) throws -> CGImage {
        let heatmap = try generateHeatmapVisualization(prediction: prediction)
        
        // Create context for blending
        let width = originalImage.width
        let height = originalImage.height
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw VisualizationError.contextCreationFailed
        }
        
        // Draw original image
        context.draw(originalImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Draw heatmap with alpha
        context.setAlpha(CGFloat(configuration.overlayAlpha))
        context.draw(heatmap, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let result = context.makeImage() else {
            throw VisualizationError.imageGenerationFailed
        }
        
        return result
    }
    
    /// Generate side-by-side visualization
    private func generateSideBySideVisualization(
        prediction: UNetPrediction,
        originalImage: CGImage
    ) throws -> CGImage {
        let heatmap = try generateHeatmapVisualization(prediction: prediction)
        
        let width = originalImage.width * 2
        let height = originalImage.height
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw VisualizationError.contextCreationFailed
        }
        
        // Draw original on left
        context.draw(originalImage, in: CGRect(x: 0, y: 0, width: originalImage.width, height: height))
        
        // Draw heatmap on right
        context.draw(heatmap, in: CGRect(x: originalImage.width, y: 0, width: originalImage.width, height: height))
        
        guard let result = context.makeImage() else {
            throw VisualizationError.imageGenerationFailed
        }
        
        return result
    }
    
    /// Generate grid visualization for all channels
    private func generateGridVisualization(prediction: UNetPrediction) throws -> CGImage {
        let channels = prediction.channels
        guard !channels.isEmpty else {
            throw VisualizationError.noChannelsToVisualize
        }
        
        // Calculate grid dimensions
        let gridSize = Int(ceil(sqrt(Double(channels.count))))
        let cellWidth = channels[0].width
        let cellHeight = channels[0].height
        let padding = 2
        
        let totalWidth = (cellWidth + padding) * gridSize - padding
        let totalHeight = (cellHeight + padding) * gridSize - padding
        
        guard let context = CGContext(
            data: nil,
            width: totalWidth,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: totalWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw VisualizationError.contextCreationFailed
        }
        
        // Fill background
        context.setFillColor(CGColor(gray: 0.1, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))
        
        // Draw each channel
        for (index, channel) in channels.enumerated() {
            let row = index / gridSize
            let col = index % gridSize
            
            let x = col * (cellWidth + padding)
            let y = row * (cellHeight + padding)
            
            if let channelImage = channel.toCGImage(colorMap: configuration.colorMap) {
                context.draw(channelImage, in: CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
            }
        }
        
        guard let result = context.makeImage() else {
            throw VisualizationError.imageGenerationFailed
        }
        
        return result
    }
    
    /// Generate animated visualization (returns first frame)
    private func generateAnimatedVisualization(prediction: UNetPrediction) throws -> CGImage {
        // For animated visualization, we return the first frame
        // The actual animation would be handled by the UI layer
        return try generateHeatmapVisualization(prediction: prediction)
    }
    
    /// Setup Combine bindings
    private func setupBindings() {
        performanceMonitor.$currentFPS
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentFPS)
    }
}

/// Result of visualization processing
public struct VisualizationResult {
    public let prediction: UNetPrediction
    public let visualizedImage: CGImage
    public let performanceMetrics: PerformanceMonitor.PerformanceMetrics
}

/// Errors that can occur during visualization
public enum VisualizationError: LocalizedError {
    case imageGenerationFailed
    case contextCreationFailed
    case noChannelsToVisualize
    
    public var errorDescription: String? {
        switch self {
        case .imageGenerationFailed:
            return "Failed to generate visualization image"
        case .contextCreationFailed:
            return "Failed to create graphics context"
        case .noChannelsToVisualize:
            return "No channels available for visualization"
        }
    }
}

/// Extension for cache key generation
private extension CGImage {
    var cacheKey: String? {
        guard let dataProvider = self.dataProvider,
              let data = dataProvider.data else { return nil }
        
        let bytes = CFDataGetBytePtr(data)
        let length = min(CFDataGetLength(data), 1024) // Use first 1KB for key
        
        var hash = 0
        for i in 0..<length {
            hash = hash &* 31 &+ Int(bytes![i])
        }
        
        return "\(width)x\(height)_\(hash)"
    }
}
