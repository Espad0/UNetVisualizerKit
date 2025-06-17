# Contributing to UNetVisualizerKit

First off, thank you for considering contributing to UNetVisualizerKit! It's people like you that make UNetVisualizerKit such a great tool.

## Code of Conduct

This project and everyone participating in it is governed by our Code of Conduct. By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

* **Use a clear and descriptive title**
* **Describe the exact steps which reproduce the problem**
* **Provide specific examples to demonstrate the steps**
* **Describe the behavior you observed after following the steps**
* **Explain which behavior you expected to see instead and why**
* **Include screenshots and animated GIFs** if possible
* **Include device information** (iPhone model, iOS version)
* **Include crash logs** if applicable

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

* **Use a clear and descriptive title**
* **Provide a step-by-step description of the suggested enhancement**
* **Provide specific examples to demonstrate the steps**
* **Describe the current behavior** and **explain which behavior you expected to see instead**
* **Explain why this enhancement would be useful**

### Pull Requests

1. Fork the repo and create your branch from `main`
2. If you've added code that should be tested, add tests
3. If you've changed APIs, update the documentation
4. Ensure the test suite passes
5. Make sure your code follows the existing code style
6. Issue that pull request!

### Code Style

* Use Swift's standard naming conventions
* Follow the existing code formatting
* Add documentation comments for public APIs
* Keep functions focused and small
* Write self-documenting code

Example:
```swift
/// Processes the input image and returns visualization result
/// - Parameters:
///   - image: The input image to process
/// - Returns: The visualization result containing prediction and performance metrics
/// - Throws: `ModelError` if processing fails
public func process(_ image: CGImage) async throws -> VisualizationResult {
    // Implementation
}
```

### Documentation

* Update README.md if you change functionality
* Add inline documentation for public APIs
* Update tutorials if adding new features
* Include code examples in documentation

## Project Structure

```
Sources/UNetVisualizerKit/
├── Core/                    # 🧠 Neural Network & Processing Engine
│   ├── UNetModel.swift     # Core ML model wrapper with prediction pipeline
│   ├── UNetVisualizer.swift # Main visualizer class with processing logic
│   └── CameraView.swift    # Real-time camera capture integration
├── Visualization/           # 🎨 Rendering & Display Engine
│   ├── VisualizerView.swift # Main visualization view component
│   ├── ColorMap.swift      # Color mapping utilities (Viridis, Grayscale, etc.)
│   ├── DemoVisualizationView.swift # Complete demo UI with photo picker
│   ├── FullScreenImageView.swift   # Full-screen image viewing component
│   └── HelperViews.swift   # UI helper components (PlaceholderView, etc.)
├── Performance/             # ⚡ Monitoring & Optimization
│   ├── PerformanceMonitor.swift # FPS tracking, latency measurement
│   └── ImageCache.swift    # Memory-efficient image caching system
├── Models/                  # 📋 Data Structures & Protocols
└── Extensions/              # 🔧 Helper Extensions
```

## Commit Messages

* Use the present tense ("Add feature" not "Added feature")
* Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
* Limit the first line to 72 characters or less
* Reference issues and pull requests liberally after the first line

Example:
```
Add real-time performance monitoring

- Implement FPS counter
- Add inference time tracking
- Create performance overlay view

Fixes #123
```

## Review Process

1. A team member will review your pull request
2. They may suggest changes or improvements
3. Make the requested changes and push to your branch
4. Once approved, your PR will be merged

## Recognition

Contributors will be recognized in:
* The project README
* Release notes
* The contributors page

## Questions?

Feel free to open an issue with your question or reach out to the maintainers directly.

Thank you for contributing! 🎉