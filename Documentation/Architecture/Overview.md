# Architecture Overview

UNetVisualizerKit is designed with modularity, performance, and ease of use in mind. This document provides a comprehensive overview of the framework's architecture.

## Design Principles

1. **Modularity**: Clear separation of concerns with distinct components
2. **Performance**: Optimized for real-time processing on mobile devices
3. **Flexibility**: Configurable visualization modes and processing options
4. **Type Safety**: Leveraging Swift's type system for compile-time safety
5. **Testability**: Designed with unit testing and mocking in mind

## Core Components

```
UNetVisualizerKit/
├── Core/
│   ├── UNetModel.swift           # Core ML model wrapper
│   └── UNetModelProtocol.swift   # Model abstraction
├── Visualization/
│   ├── ColorMap.swift            # Color mapping algorithms
│   ├── VisualizerView.swift      # SwiftUI components
│   └── Renderers/                # Visualization renderers
├── Performance/
│   ├── PerformanceMonitor.swift  # FPS and metrics tracking
│   └── ImageCache.swift          # LRU cache implementation
└── UNetVisualizer.swift          # Main orchestrator
```

## Component Details

### 1. Core Layer

#### UNetModel
- Wraps Core ML models with a clean interface
- Handles model loading and configuration
- Manages input preprocessing and output postprocessing
- Provides error handling and validation

```swift
public protocol UNetModelProtocol {
    var inputSize: CGSize { get }
    var outputChannels: Int { get }
    func predict(_ image: CGImage) async throws -> UNetPrediction
}
```

Key responsibilities:
- Model lifecycle management
- GPU/CPU computation unit selection
- Input normalization
- Output tensor processing

### 2. Visualization Layer

#### ColorMap
Provides various color mapping algorithms for converting prediction values to colors:
- Scientific colormaps (Viridis, Plasma, Inferno, Magma)
- Classic heatmap
- Rainbow/HSV mapping
- Custom color interpolation

#### Visualization Modes
- **Heatmap**: Direct visualization of prediction values
- **Overlay**: Alpha-blended overlay on original image
- **Side-by-side**: Original and prediction comparison
- **Grid**: All channels displayed in a grid
- **Animated**: Time-based channel cycling

### 3. Performance Layer

#### PerformanceMonitor
Real-time performance tracking with:
- FPS calculation (current, average, min, max)
- Inference time statistics
- Memory usage monitoring
- Performance alerts

```swift
public struct PerformanceMetrics {
    let currentFPS: Double
    let averageInferenceTime: Double
    let memoryUsageMB: Double
    // ... more metrics
}
```

#### ImageCache
LRU (Least Recently Used) cache implementation:
- Thread-safe concurrent access
- Configurable size limits
- Automatic eviction
- Hit/miss statistics

### 4. Main Orchestrator

#### UNetVisualizer
The main class that coordinates all components:

```swift
@MainActor
public final class UNetVisualizer: ObservableObject {
    @Published public private(set) var isProcessing: Bool
    @Published public private(set) var currentFPS: Double
    @Published public private(set) var visualizationImage: CGImage?
    
    public func process(_ image: CGImage) async throws -> VisualizationResult
    public func processStream(_ images: AsyncStream<CGImage>) async throws
}
```

## Data Flow

```
Input Image (CGImage)
    ↓
[Image Preprocessing]
    ↓
[Core ML Inference] ← → [Performance Monitor]
    ↓
[Output Processing]
    ↓
[Visualization Pipeline]
    ├── Channel Selection
    ├── Color Mapping
    └── Rendering
    ↓
[Cache Storage] ← → [Memory Management]
    ↓
Output (VisualizationResult)
```

## Threading Model

1. **Main Thread**: UI updates, SwiftUI integration
2. **Processing Queue**: Model inference, image processing
3. **Metrics Queue**: Performance monitoring updates
4. **Cache Queue**: Thread-safe cache operations

## Memory Management

### Strategies
1. **Automatic Reference Counting**: Standard Swift memory management
2. **Weak References**: For delegate patterns and observers
3. **Cache Limits**: Configurable maximum cache size
4. **Image Compression**: Optional for cache storage

### Best Practices
```swift
// Use autoreleasepool for batch processing
for image in images {
    autoreleasepool {
        let result = try await visualizer.process(image)
        // Process result
    }
}
```

## Error Handling

Comprehensive error types for different failure scenarios:

```swift
public enum ModelError: LocalizedError {
    case invalidModelURL
    case modelLoadingFailed(Error)
    case predictionFailed(Error)
    // ...
}

public enum VisualizationError: LocalizedError {
    case imageGenerationFailed
    case contextCreationFailed
    // ...
}
```

## Extension Points

### Custom Color Maps
```swift
let customColorMap = ColorMap.custom([
    (0.0, RGBColor(0, 0, 255)),    // Blue for low values
    (0.5, RGBColor(255, 255, 255)), // White for medium
    (1.0, RGBColor(255, 0, 0))      // Red for high values
])
```

### Custom Visualization Modes
Extend the visualization pipeline by:
1. Subclassing visualization components
2. Implementing custom renderers
3. Adding new visualization modes

### Performance Optimizations
- Custom preprocessing pipelines
- Model quantization support
- Batch processing optimizations

## Platform Considerations

### iOS Specific
- Metal Performance Shaders integration
- Vision framework optimizations
- UIKit and SwiftUI dual support

### Hardware Acceleration
- Automatic GPU utilization
- Neural Engine support for A12+ chips
- Fallback to CPU when needed

## Testing Architecture

### Unit Testing
- Protocol-based design for easy mocking
- Isolated component testing
- Performance benchmarking

### Integration Testing
- End-to-end visualization pipeline
- Memory leak detection
- Thread safety verification

## Future Extensibility

The architecture supports future enhancements:
1. **Additional Model Types**: Beyond U-Net architectures
2. **3D Visualization**: For volumetric predictions
3. **Video Processing**: Temporal consistency
4. **Cloud Integration**: Remote model inference
5. **AR Integration**: Real-world overlay

---

For implementation details, see the [API Reference](../API/Reference.md).