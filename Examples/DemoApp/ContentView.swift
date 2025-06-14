import SwiftUI
import PhotosUI
import UNetVisualizerKit
import CoreML

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var processedResult: VisualizationResult?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showFullScreenImage = false
    @State private var selectedChannelIndex: Int? = nil
    
    @StateObject private var visualizer: UNetVisualizer = {
        do {
            
            // Replace "YourModelName" with your actual model file name
            let modelHandler = try UNetModelHandler(modelName: "SegmentationModel")
            
            return UNetVisualizer(modelHandler: modelHandler)
        } catch {
            fatalError("Failed to load model: \(error)")
        }
    }()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Image selection area
                photoPicker
                
                // Visualization result
                if let result = processedResult {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Results")
                            .font(.headline)
                        
                        // Performance metrics
                        HStack {
                            Label("\(String(format: "%.1f", result.performanceMetrics.currentFPS)) FPS", systemImage: "speedometer")
                            Spacer()
                            Label("\(String(format: "%.1f", result.prediction.inferenceTime))ms", systemImage: "timer")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        // Channel heatmaps
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Channel Heatmaps (\(result.prediction.channels.count) channels)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(result.prediction.channels, id: \.index) { channel in
                                        VStack(spacing: 4) {
                                            Text("Channel \(channel.index)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            
                                            if let heatmapImage = channel.toCGImage(colorMap: visualizer.currentConfiguration.colorMap) {
                                                Image(uiImage: UIImage(cgImage: heatmapImage))
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fit)
                                                    .frame(width: 150, height: 150)
                                                    .cornerRadius(8)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                                    )
                                                    .onTapGesture {
                                                        selectedChannelIndex = channel.index
                                                        showFullScreenImage = true
                                                    }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                            .frame(height: 180)
                        }
                        
                        // Original visualized image
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Combined Visualization")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Image(uiImage: UIImage(cgImage: result.visualizedImage))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 150)
                                .cornerRadius(8)
                                .onTapGesture {
                                    selectedChannelIndex = nil
                                    showFullScreenImage = true
                                }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 16) {
                    Button(action: processCurrentImage) {
                        Label("Process", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedImage == nil || isProcessing)
                    
                    Button(action: shareResult) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(processedResult == nil)
                }
            }
            .padding()
            .navigationTitle("U-Net Visualizer Demo")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: DemoSettingsView(visualizer: visualizer)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .fullScreenCover(isPresented: $showFullScreenImage) {
            if let result = processedResult {
                if let channelIndex = selectedChannelIndex,
                   let channel = result.prediction.channel(channelIndex),
                   let heatmapImage = channel.toCGImage(colorMap: visualizer.currentConfiguration.colorMap) {
                    FullScreenImageView(image: UIImage(cgImage: heatmapImage))
                } else {
                    FullScreenImageView(image: UIImage(cgImage: result.visualizedImage))
                }
            }
        }
    }
    
    private func processCurrentImage() {
        guard let image = selectedImage else { return }
        Task {
            await processImage(image)
        }
    }
    
    @MainActor
    private func processImage(_ uiImage: UIImage) async {
        guard let cgImage = uiImage.cgImage else {
            showError(message: "Failed to convert image")
            return
        }
        
        isProcessing = true
        errorMessage = nil
        
        do {
            let result = try await visualizer.process(cgImage)
            processedResult = result
        } catch {
            showError(message: error.localizedDescription)
        }
        
        isProcessing = false
    }
    
    private func shareResult() {
        guard let result = processedResult else { return }
        
        let image = UIImage(cgImage: result.visualizedImage)
        
        let activityVC = UIActivityViewController(
            activityItems: [image, result.performanceMetrics.report],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
    
    // MARK: - Photo Picker Helpers
    @ViewBuilder
    private var photoPicker: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            pickerContent
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    selectedImage = uiImage
                    await processImage(uiImage)
                }
            }
        }
    }

    @ViewBuilder
    private var pickerContent: some View {
        if let selectedImage = selectedImage {
            SelectedImageView(uiImage: selectedImage, isProcessing: isProcessing)
        } else {
            PlaceholderView()
        }
    }
}

// MARK: - Demo Settings View
struct DemoSettingsView: View {
    @ObservedObject var visualizer: UNetVisualizer
    
    var body: some View {
        Form {
            Section("Visualization") {
                Picker("Mode", selection: modeBinding) {
                    Text("Heatmap").tag(UNetVisualizer.ChannelVisualizationMode.heatmap)
                    Text("Overlay").tag(UNetVisualizer.ChannelVisualizationMode.overlay)
                    Text("Side by Side").tag(UNetVisualizer.ChannelVisualizationMode.sideBySide)
                    Text("Grid").tag(UNetVisualizer.ChannelVisualizationMode.grid)
                }
                
                Picker("Color Map", selection: colorMapBinding) {
                    Text("Viridis").tag(ColorMap.viridis)
                    Text("Plasma").tag(ColorMap.plasma)
                    Text("Inferno").tag(ColorMap.inferno)
                    Text("Magma").tag(ColorMap.magma)
                    Text("Heatmap").tag(ColorMap.heatmap)
                    Text("Rainbow").tag(ColorMap.rainbow)
                }
            }
            
            Section("Performance") {
                Toggle("Show FPS Overlay", isOn: showPerformanceBinding)
                
                Stepper("Target FPS: \(targetFPSBinding.wrappedValue)",
                       value: targetFPSBinding,
                       in: 15...60,
                       step: 15)
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Framework")
                    Spacer()
                    Text("UNetVisualizerKit")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var modeBinding: Binding<UNetVisualizer.ChannelVisualizationMode> {
        Binding(
            get: { visualizer.currentConfiguration.channelVisualization },
            set: { newValue in visualizer.configure { $0.channelVisualization = newValue } }
        )
    }
    
    private var colorMapBinding: Binding<ColorMap> {
        Binding(
            get: { visualizer.currentConfiguration.colorMap },
            set: { newValue in visualizer.configure { $0.colorMap = newValue } }
        )
    }
    
    private var showPerformanceBinding: Binding<Bool> {
        Binding(
            get: { visualizer.currentConfiguration.showPerformanceOverlay },
            set: { newValue in visualizer.configure { $0.showPerformanceOverlay = newValue } }
        )
    }
    
    private var targetFPSBinding: Binding<Int> {
        Binding(
            get: { visualizer.currentConfiguration.targetFPS },
            set: { newValue in visualizer.configure { $0.targetFPS = newValue } }
        )
    }
}

// MARK: - Full Screen Image View
struct FullScreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .offset(y: dragOffset.height)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { value in
                                    lastScale = scale
                                    withAnimation(.spring()) {
                                        if scale < 1.0 {
                                            scale = 1.0
                                            lastScale = 1.0
                                            offset = .zero
                                            lastOffset = .zero
                                        } else if scale > 5.0 {
                                            scale = 5.0
                                            lastScale = 5.0
                                        }
                                    }
                                }
                        )
                        .gesture(
                            scale > 1.0 ? DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { value in
                                    lastOffset = offset
                                } : nil
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                    lastScale = 2.0
                                }
                            }
                        }
                }
            }
            .background(Color.black)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if scale == 1.0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        if scale == 1.0 {
                            if value.translation.height > 100 {
                                dismiss()
                            } else {
                                withAnimation(.spring()) {
                                    dragOffset = .zero
                                }
                            }
                        }
                    }
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Helper Views

/// Displays the selected image together with an optional overlay when processing.
struct SelectedImageView: View {
    let uiImage: UIImage
    let isProcessing: Bool

    var body: some View {
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 300)
            .overlay(alignment: .topTrailing) {
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding()
                }
            }
    }
}

/// Placeholder that is shown when no image has been selected yet.
struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("Tap to select an image")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 300)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    ContentView()
}
