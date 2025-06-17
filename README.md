# UNetVisualizerKit 

A production-ready iOS framework for visualizing U-Net neural network predictions with real-time performance monitoring.

![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![iOS](https://img.shields.io/badge/iOS-15.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![Build](https://img.shields.io/badge/Build-Passing-brightgreen.svg)

## 🎯 Mission

Computer vision developers often need to test their neural nets on devices: how they perform, what they predict. This repo helps developers visualize and debug neural network predictions on iOS devices by providing:
- 📱 **Real-time visualization** of U-Net style CNNs predictions with channel-specific views
- 🎨 **Model output** – renders per-channel masks, alpha-blends them over live camera or still images
- ⚡ **Performance metrics** – live FPS, per-inference latency, and energy-impact read-outs tell you exactly how your network behaves in production.


## 🚀 Quick Start

Getting started is incredibly simple - just 3 steps:

### 1. Add the Package
In Xcode: **File → Add Package Dependencies** → `https://github.com/andrejnesterov/UNetVisualizerKit`

### 2. Copy the Demo ContentView
Copy `Examples/DemoApp/ContentView.swift` into your project:

```swift
import SwiftUI
import UNetVisualizerKit

struct ContentView: View {
    var body: some View {
        DemoVisualizationView(modelHandler: createModelHandler())
    }
    
    private func createModelHandler() -> UNetModelHandler {
        do {
            let modelHandler = try UNetModelHandler(modelName: "YourModelName")
            return modelHandler
        } catch {
            fatalError("Failed to load model: \(error)")
        }
    }
}
```

### 3. Replace Model Name & Run
Change `"YourModelName"` to your Core ML model name → Build & Run!

You'll get a complete visualization app with photo picker, camera, real-time processing, and performance metrics.

## 📱 Examples

TODO: provide image examples

## 🏗 Architecture

UNetVisualizerKit follows a modular architecture designed for performance, maintainability, and ease of use. The framework is organized into five main layers:

### 📦 Core Components

```
Sources/UNetVisualizerKit/
├── Core/                    # 🧠 Neural Network & Processing Engine
│   ├── UNetModel.swift     # Core ML model wrapper with prediction pipeline
│   └── CameraView.swift    # Real-time camera capture integration
├── Visualization/           # 🎨 Rendering & Display Engine
│   ├── VisualizerView.swift # Main visualization view component
│   └── ColorMap.swift      # Color mapping utilities (Viridis, Grayscale, etc.)
├── Performance/             # ⚡ Monitoring & Optimization
│   ├── PerformanceMonitor.swift # FPS tracking, latency measurement
│   └── ImageCache.swift    # Memory-efficient image caching system
├── Models/                  # 📋 Data Structures & Protocols
└── Extensions/              # 🔧 Helper Extensions
```

### 🔄 Data Flow Architecture

```
Input Source → Model Handler → Visualizer → UI Components
     ↓              ↓             ↓           ↓
📷 Camera      🧠 UNetModel   🎨 Renderer   📱 SwiftUI
📷 Photos      ⚡ Inference   🎯 ColorMap   🖼️ Views
🖼️ Images      📊 Channels    🔄 Cache      📈 Metrics
```

### 🎯 Key Classes & Responsibilities

#### **UNetModelHandler** - Neural Network Interface
- **Purpose**: Abstracts Core ML model loading and prediction
- **Features**: Automatic input preprocessing, output channel extraction, async prediction
- **Input**: CGImage, MLMultiArray
- **Output**: UNetPrediction with channel data and metrics

#### **UNetVisualizer** - Main Orchestrator
- **Purpose**: Coordinates model processing with visualization rendering
- **Features**: Real-time processing, configurable visualization modes, performance monitoring
- **Modes**: Heatmap, Overlay, Side-by-side, Grid, Animated

#### **DemoVisualizationView** - Complete UI Demo
- **Purpose**: Production-ready UI showcasing all framework capabilities
- **Features**: Photo picker, camera integration, channel visualization, performance metrics
- **Optimizations**: Image caching, background processing, memory management

#### **PerformanceMonitor** - Real-time Metrics
- **Purpose**: Tracks inference performance and system resource usage
- **Metrics**: FPS, inference latency, memory usage, energy impact

#### **ColorMap** - Visualization Styling
- **Purpose**: Provides scientific-grade color mapping for neural network outputs
- **Maps**: Viridis, Plasma, Inferno, Grayscale, Custom gradients

### 🏛️ Design Principles

- **🔌 Pluggable**: Swap models, visualizations, and UI components independently
- **⚡ Performance-First**: Async processing, intelligent caching, memory optimization
- **🧪 Production-Ready**: Comprehensive error handling, resource management, platform compatibility
- **📱 SwiftUI Native**: Modern declarative UI with Combine integration
- **🔍 Developer-Friendly**: Rich debugging information, performance insights, extensible APIs


## 📖 Documentation

### For Junior Developers
- [Getting Started Guide](Documentation/Tutorials/GettingStarted.md)
- [Understanding U-Net Models](Documentation/Tutorials/UnderstandingUNet.md)
- [Basic Integration Tutorial](Documentation/Tutorials/BasicIntegration.md)

### For Middle Developers
- [Architecture Overview](Documentation/Architecture/Overview.md)
- [Performance Optimization](Documentation/Architecture/Performance.md)
- [Custom Visualizations](Documentation/Tutorials/CustomVisualizations.md)

### For Senior Developers
- [API Reference](Documentation/API/Reference.md)
- [Enterprise Integration](Documentation/Architecture/Enterprise.md)
- [Contributing Guidelines](CONTRIBUTING.md)

## 🔧 Requirements

- iOS 15.0+
- Xcode 15.0+
- Swift 5.9+
- Core ML compatible device

## 💡 Use Cases

- **Medical Imaging** - Visualize segmentation masks
- **Autonomous Vehicles** - Debug perception models
- **AR Applications** - Real-time segmentation
- **Research** - Model evaluation and debugging

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Apple Core ML team for the excellent framework
- The iOS ML community for inspiration and feedback

---

**Built with ❤️ for the iOS ML community**