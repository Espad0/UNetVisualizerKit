import SwiftUI
import CoreML
import Vision

/// SwiftUI view for displaying U-Net visualizations with performance overlay
public struct UNetVisualizerView: View {
    @StateObject private var visualizer: UNetVisualizer
    @State private var selectedChannel: Int = 0
    @State private var showSettings: Bool = false
    
    private let modelURL: URL
    
    public init(modelURL: URL) {
        self.modelURL = modelURL
        self._visualizer = StateObject(wrappedValue: {
            do {
                return try UNetVisualizer(modelURL: modelURL)
            } catch {
                fatalError("Failed to initialize visualizer: \(error)")
            }
        }())
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main visualization
                if let cgImage = visualizer.visualizationImage {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                } else {
                    // Fallback for iOS < 17
                    if #available(iOS 17.0, macOS 14.0, *) {
                        ContentUnavailableView(
                            "No Visualization",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("Process an image to see visualization")
                        )
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 64))
                                .foregroundColor(.secondary)
                            Text("No Visualization")
                                .font(.title2)
                                .foregroundColor(.primary)
                            Text("Process an image to see visualization")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                
                // Performance overlay
                if visualizer.currentConfiguration.showPerformanceOverlay {
                    PerformanceOverlayView(visualizer: visualizer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding()
                }
                
                // Controls overlay
                VStack {
                    Spacer()
                    ControlsView(visualizer: visualizer, selectedChannel: $selectedChannel)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding()
                }
            }
        }
        .navigationTitle("U-Net Visualizer")
        #if os(iOS)
        .navigationBarItems(trailing: Button(action: { showSettings.toggle() }) {
            Image(systemName: "gearshape")
        })
        #endif
        .sheet(isPresented: $showSettings) {
            SettingsView(visualizer: visualizer)
        }
    }
}

/// Performance overlay showing FPS and inference time
struct PerformanceOverlayView: View {
    @ObservedObject var visualizer: UNetVisualizer
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // FPS indicator
            HStack(spacing: 4) {
                Text("FPS:")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                
                Text(String(format: "%.1f", visualizer.currentFPS))
                    .font(.caption.monospaced().bold())
                    .foregroundColor(fpsColor)
            }
            
            // Inference time
            HStack(spacing: 4) {
                Text("Inference:")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                
                Text(String(format: "%.1fms", visualizer.averageInferenceTime))
                    .font(.caption.monospaced().bold())
                    .foregroundColor(.primary)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
    
    private var fpsColor: Color {
        let alert = PerformanceAlert.level(
            for: visualizer.currentFPS,
            target: Double(visualizer.currentConfiguration.targetFPS)
        )
        
        switch alert {
        case .none: return .green
        case .low: return .yellow
        case .medium: return .orange
        case .high: return .red
        }
    }
}

/// Controls for visualization modes and channels
struct ControlsView: View {
    @ObservedObject var visualizer: UNetVisualizer
    @Binding var selectedChannel: Int
    
    var body: some View {
        VStack(spacing: 12) {
            // Visualization mode picker
            Picker("Mode", selection: modeBinding) {
                Text("Heatmap").tag(UNetVisualizer.ChannelVisualizationMode.heatmap)
                Text("Overlay").tag(UNetVisualizer.ChannelVisualizationMode.overlay)
                Text("Side by Side").tag(UNetVisualizer.ChannelVisualizationMode.sideBySide)
                Text("Grid").tag(UNetVisualizer.ChannelVisualizationMode.grid)
            }
            .pickerStyle(.segmented)
            
            // Channel selector (if multiple channels)
            if let prediction = visualizer.lastPrediction,
               prediction.channels.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Channel: \(selectedChannel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(
                        value: Binding(
                            get: { Double(selectedChannel) },
                            set: { selectedChannel = Int($0) }
                        ),
                        in: 0...Double(prediction.channels.count - 1),
                        step: 1
                    )
                }
            }
            
            // Color map picker
            HStack {
                Text("Color Map:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Color Map", selection: colorMapBinding) {
                    Text("Viridis").tag(ColorMap.viridis)
                    Text("Plasma").tag(ColorMap.plasma)
                    Text("Inferno").tag(ColorMap.inferno)
                    Text("Heatmap").tag(ColorMap.heatmap)
                }
                .pickerStyle(.menu)
            }
        }
    }
    
    private var modeBinding: Binding<UNetVisualizer.ChannelVisualizationMode> {
        Binding(
            get: { visualizer.currentConfiguration.channelVisualization },
            set: { mode in
                visualizer.configure { config in
                    config.channelVisualization = mode
                }
            }
        )
    }
    
    private var colorMapBinding: Binding<ColorMap> {
        Binding(
            get: { visualizer.currentConfiguration.colorMap },
            set: { colorMap in
                visualizer.configure { config in
                    config.colorMap = colorMap
                }
            }
        )
    }
}

/// Settings view for configuration
struct SettingsView: View {
    @ObservedObject var visualizer: UNetVisualizer
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Performance") {
                    Toggle("Show Performance Overlay", isOn: showPerformanceBinding)
                    
                    HStack {
                        Text("Target FPS")
                        Spacer()
                        Picker("Target FPS", selection: targetFPSBinding) {
                            Text("30").tag(30)
                            Text("60").tag(60)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                
                Section("Visualization") {
                    HStack {
                        Text("Overlay Opacity")
                        Slider(value: overlayAlphaBinding, in: 0...1)
                    }
                }
                
                Section("Caching") {
                    Toggle("Enable Caching", isOn: enableCachingBinding)
                    
                    if visualizer.currentConfiguration.enableCaching {
                        HStack {
                            Text("Max Cache Size")
                            Spacer()
                            Text("\(visualizer.currentConfiguration.maxCacheSize) MB")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Model Info") {
                    HStack {
                        Text("Input Size")
                        Spacer()
                        Text("\(Int(visualizer.modelInputSize.width))×\(Int(visualizer.modelInputSize.height))")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Output Channels")
                        Spacer()
                        Text("\(visualizer.modelOutputChannels)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(iOS)
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
            #endif
        }
    }
    
    private var showPerformanceBinding: Binding<Bool> {
        Binding(
            get: { visualizer.currentConfiguration.showPerformanceOverlay },
            set: { value in
                visualizer.configure { config in
                    config.showPerformanceOverlay = value
                }
            }
        )
    }
    
    private var targetFPSBinding: Binding<Int> {
        Binding(
            get: { visualizer.currentConfiguration.targetFPS },
            set: { value in
                visualizer.configure { config in
                    config.targetFPS = value
                }
            }
        )
    }
    
    private var overlayAlphaBinding: Binding<Float> {
        Binding(
            get: { visualizer.currentConfiguration.overlayAlpha },
            set: { value in
                visualizer.configure { config in
                    config.overlayAlpha = value
                }
            }
        )
    }
    
    private var enableCachingBinding: Binding<Bool> {
        Binding(
            get: { visualizer.currentConfiguration.enableCaching },
            set: { value in
                visualizer.configure { config in
                    config.enableCaching = value
                }
            }
        )
    }
}
