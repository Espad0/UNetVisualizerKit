# Getting Started with UNetVisualizerKit

Welcome to UNetVisualizerKit! This guide will help you integrate U-Net visualization into your iOS app in just a few minutes.

## Prerequisites

- iOS 15.0+ deployment target
- Xcode 15.0+
- A Core ML model file (.mlmodel) trained for segmentation
- Basic knowledge of Swift and SwiftUI/UIKit

## Installation

### Swift Package Manager

1. In Xcode, go to **File → Add Package Dependencies**
2. Enter the repository URL: `https://github.com/yourusername/UNetVisualizerKit`
3. Click **Add Package**

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'UNetVisualizerKit', '~> 1.0'
```

Then run:
```bash
pod install
```

## Basic Integration

### Step 1: Import the Framework

```swift
import UNetVisualizerKit
```

### Step 2: Initialize the Visualizer

```swift
// Assuming you have a Core ML model in your bundle
let modelURL = Bundle.main.url(forResource: "MyUNetModel", withExtension: "mlmodel")!

do {
    let visualizer = try UNetVisualizer(modelURL: modelURL)
} catch {
    print("Failed to initialize: \(error)")
}
```

### Step 3: Process an Image

```swift
// Convert your UIImage to CGImage
guard let cgImage = uiImage.cgImage else { return }

// Process the image
Task {
    do {
        let result = try await visualizer.process(cgImage)
        
        // Use the visualization
        let visualizedImage = result.visualizedImage
        let inferenceTime = result.prediction.inferenceTime
        
        print("Inference took \(inferenceTime)ms")
    } catch {
        print("Processing failed: \(error)")
    }
}
```

## SwiftUI Integration

For SwiftUI apps, use the provided `UNetVisualizerView`:

```swift
struct ContentView: View {
    let modelURL = Bundle.main.url(forResource: "MyModel", withExtension: "mlmodel")!
    
    var body: some View {
        NavigationView {
            UNetVisualizerView(modelURL: modelURL)
        }
    }
}
```

## UIKit Integration

For UIKit apps, create a view controller:

```swift
class VisualizerViewController: UIViewController {
    private var visualizer: UNetVisualizer!
    private let imageView = UIImageView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup visualizer
        do {
            let modelURL = Bundle.main.url(forResource: "MyModel", withExtension: "mlmodel")!
            visualizer = try UNetVisualizer(modelURL: modelURL)
        } catch {
            print("Failed to setup: \(error)")
        }
        
        // Setup UI
        setupUI()
    }
    
    func processImage(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        
        Task {
            do {
                let result = try await visualizer.process(cgImage)
                
                await MainActor.run {
                    self.imageView.image = UIImage(cgImage: result.visualizedImage)
                }
            } catch {
                print("Processing failed: \(error)")
            }
        }
    }
}
```

## Configuration Options

Customize the visualization behavior:

```swift
visualizer.configure {
    // Choose visualization mode
    $0.channelVisualization = .heatmap  // or .overlay, .sideBySide, .grid
    
    // Select color map
    $0.colorMap = .viridis  // or .plasma, .inferno, .heatmap
    
    // Performance settings
    $0.showPerformanceOverlay = true
    $0.targetFPS = 30
    
    // Overlay settings
    $0.overlayAlpha = 0.5
    
    // Caching
    $0.enableCaching = true
    $0.maxCacheSize = 100  // MB
}
```

## Common Use Cases

### Medical Image Segmentation

```swift
// Configure for medical imaging
visualizer.configure {
    $0.colorMap = .plasma
    $0.channelVisualization = .overlay
    $0.overlayAlpha = 0.3
}
```

### Real-time Processing

```swift
// Setup for camera feed
let cameraStream = setupCameraStream()  // Your camera setup

Task {
    try await visualizer.processStream(cameraStream)
}
```

### Multi-channel Analysis

```swift
// Access individual channels
let result = try await visualizer.process(image)

for (index, channel) in result.prediction.channels.enumerated() {
    print("Channel \(index): min=\(channel.minValue), max=\(channel.maxValue)")
    
    // Visualize specific channel
    if let channelImage = channel.toCGImage(colorMap: .viridis) {
        // Use channel visualization
    }
}
```

## Performance Tips

1. **Enable Caching**: For repeated processing of similar images
2. **Adjust Target FPS**: Lower for battery efficiency, higher for smoothness
3. **Use GPU**: Enabled by default for optimal performance
4. **Batch Processing**: Process multiple images concurrently when possible

## Troubleshooting

### Model Loading Fails

Ensure your model:
- Is properly added to your app bundle
- Has correct input dimensions (typically 256×256 or 512×512)
- Outputs multi-array data

### Low FPS

Try:
- Reducing input image size
- Lowering target FPS
- Enabling caching
- Using a smaller model

### Memory Issues

- Reduce cache size
- Process smaller batches
- Use autorelease pools for batch processing

## Next Steps

- Check out the [Architecture Overview](../Architecture/Overview.md)
- Learn about [Custom Visualizations](CustomVisualizations.md)
- Explore [Performance Optimization](../Architecture/Performance.md)

## Example Project

See the `Examples/DemoApp` folder for a complete working example.

---

Need help? [Open an issue](https://github.com/yourusername/UNetVisualizerKit/issues) on GitHub.