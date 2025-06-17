import SwiftUI
import PhotosUI
import CoreML
import CoreGraphics

#if os(iOS)
import UIKit

@available(iOS 16.0, *)
public struct DemoVisualizationView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var processedResult: VisualizationResult?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showFullScreenImage = false
    @State private var selectedChannelIndex: Int? = nil
    @State private var imageCache: [String: UIImage] = [:]
    @State private var showCamera = false
    
    @StateObject private var visualizer: UNetVisualizer
    
    public init(modelHandler: UNetModelHandler) {
        self._visualizer = StateObject(wrappedValue: UNetVisualizer(modelHandler: modelHandler))
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Image/Camera selection area
                if selectedImage == nil && processedResult == nil {
                    VStack(spacing: 20) {
                        // Photo picker
                        photoPicker
                        
                        Text("or")
                            .foregroundColor(.secondary)
                        
                        // Camera button
                        Button(action: {
                            showCamera = true
                        }) {
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                                Text("Tap to start camera")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                } else {
                    // Image selection area
                    photoPicker
                    
                    // Visualization result
                    if let result = processedResult {
                        visualizationResultView(result: result)
                    }
                }
                
                Spacer()
                
                // Action button
                if selectedImage != nil || processedResult != nil {
                    Button(action: retryImageSelection) {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)
                }
            }
            .padding()
            .navigationTitle("U-Net Visualizer Demo")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .fullScreenCover(isPresented: $showFullScreenImage) {
            if let result = processedResult {
                FullScreenImageView(
                    result: result,
                    selectedImage: selectedImage,
                    visualizer: visualizer,
                    currentIndex: $selectedChannelIndex,
                    isOverlayMode: (selectedChannelIndex ?? 0) >= 1000
                )
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            #if os(iOS)
            CameraView(visualizer: visualizer)
            #else
            Text("Camera not available on this platform")
            #endif
        }
    }
    
    // MARK: - Extracted View Components
    @ViewBuilder
    private func visualizationResultView(result: VisualizationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results")
                .font(.headline)
            
            performanceMetricsView(result: result)
            
            channelHeatmapsSection(result: result)
            
            channelOverlaysSection(result: result)
            
            combinedVisualizationSection(result: result)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func performanceMetricsView(result: VisualizationResult) -> some View {
        HStack {
            Spacer()
            Label("\(String(format: "%.1f", result.prediction.inferenceTime))ms", systemImage: "timer")
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
    
    @ViewBuilder
    private func channelHeatmapsSection(result: VisualizationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Channel Heatmaps (\(result.prediction.channels.count) channels)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            let gridColumns = [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 12)]
            
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(result.prediction.channels, id: \.index) { channel in
                    channelHeatmapItem(channel: channel)
                }
            }
        }
    }
    
    @ViewBuilder
    private func channelOverlaysSection(result: VisualizationResult) -> some View {
        if let selectedImage = selectedImage, let cgImage = selectedImage.cgImage {
            VStack(alignment: .leading, spacing: 12) {
                Text("Channel Overlays")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                let gridColumns = [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 12)]
                
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(result.prediction.channels, id: \.index) { channel in
                        channelOverlayItem(channel: channel, originalImage: cgImage)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func combinedVisualizationSection(result: VisualizationResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(uiImage: UIImage(cgImage: result.visualizedImage))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 150)
                .cornerRadius(8)
                .onTapGesture {
                    prepareFullScreenImage(channelIndex: nil, isOverlay: false)
                    showFullScreenImage = true
                }
        }
    }
    
    @ViewBuilder
    private func channelHeatmapItem(channel: ChannelData) -> some View {
        VStack(spacing: 4) {
            Text("Channel \(channel.index)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if let heatmapImage = getCachedHeatmapImage(for: channel, colorMap: visualizer.currentConfiguration.colorMap) {
                channelImageView(
                    uiImage: heatmapImage,
                    onTap: {
                        prepareFullScreenImage(channelIndex: channel.index, isOverlay: false)
                        showFullScreenImage = true
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private func channelOverlayItem(channel: ChannelData, originalImage: CGImage) -> some View {
        VStack(spacing: 4) {
            Text("Channel \(channel.index)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if let overlayImage = getCachedOverlayImage(for: channel, originalImage: originalImage, colorMap: visualizer.currentConfiguration.colorMap) {
                channelImageView(
                    uiImage: overlayImage,
                    onTap: {
                        prepareFullScreenImage(channelIndex: channel.index, isOverlay: true)
                        showFullScreenImage = true
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private func channelImageView(uiImage: UIImage, onTap: @escaping () -> Void) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(minWidth: 100, maxWidth: 150, minHeight: 100, maxHeight: 150)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .onTapGesture(perform: onTap)
    }
    
    private func processCurrentImage() {
        guard let image = selectedImage else { return }
        Task {
            await processImage(image)
        }
    }
    
    private func retryImageSelection() {
        // Reset ALL state to exactly match initial app state
        selectedItem = nil
        selectedImage = nil
        processedResult = nil
        isProcessing = false
        errorMessage = nil
        showError = false
        selectedChannelIndex = nil
        imageCache.removeAll()
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
            
            // Clear cache when new result is processed
            imageCache.removeAll()
            
            // Pre-generate commonly used images in background
            Task.detached(priority: .utility) {
                await self.preGenerateImages(for: result, originalImage: cgImage)
            }
        } catch {
            showError(message: error.localizedDescription)
        }
        
        isProcessing = false
    }
    
    
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
    
    // MARK: - Performance Optimization Helpers
    
    /// Get cached heatmap image or generate and cache it
    private func getCachedHeatmapImage(for channel: ChannelData, colorMap: ColorMap) -> UIImage? {
        let cacheKey = "heatmap_\(channel.index)_\(colorMap.hashValue)"
        
        if let cachedImage = imageCache[cacheKey] {
            return cachedImage
        }
        
        guard let cgImage = channel.toCGImage(colorMap: colorMap) else { return nil }
        let uiImage = UIImage(cgImage: cgImage)
        
        // Cache the image
        imageCache[cacheKey] = uiImage
        
        return uiImage
    }
    
    /// Get cached overlay image or generate and cache it
    private func getCachedOverlayImage(for channel: ChannelData, originalImage: CGImage, colorMap: ColorMap) -> UIImage? {
        let cacheKey = "overlay_\(channel.index)_\(colorMap.hashValue)_\(originalImage.hashValue)"
        
        if let cachedImage = imageCache[cacheKey] {
            return cachedImage
        }
        
        guard let overlayImage = createOverlayImage(
            channel: channel,
            originalImage: originalImage,
            colorMap: colorMap,
            alpha: 0.5
        ) else { return nil }
        
        let uiImage = UIImage(cgImage: overlayImage)
        
        // Cache the image
        imageCache[cacheKey] = uiImage
        
        return uiImage
    }
    
    /// Prepare full-screen image viewing by setting the appropriate index
    private func prepareFullScreenImage(channelIndex: Int?, isOverlay: Bool) {
        if let channelIndex = channelIndex {
            selectedChannelIndex = isOverlay ? channelIndex + 1000 : channelIndex
        } else {
            selectedChannelIndex = nil
        }
    }
    
    /// Pre-generate commonly accessed images in background for better performance
    @MainActor
    private func preGenerateImages(for result: VisualizationResult, originalImage: CGImage) async {
        // Pre-generate heatmap images for first few channels
        let channelsToPregenerate = min(result.prediction.channels.count, 4)
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<channelsToPregenerate {
                let channel = result.prediction.channels[i]
                
                // Pre-generate heatmap
                group.addTask { @MainActor in
                    await self.pregenerateHeatmap(for: channel)
                }
                
                // Pre-generate overlay
                group.addTask { @MainActor in
                    await self.pregenerateOverlay(for: channel, originalImage: originalImage)
                }
            }
        }
    }
    
    @MainActor
    private func pregenerateHeatmap(for channel: ChannelData) async {
        let colorMap = visualizer.currentConfiguration.colorMap
        let cacheKey = "heatmap_\(channel.index)_\(colorMap.hashValue)"
        
        guard imageCache[cacheKey] == nil else { return }
        
        if let cgImage = channel.toCGImage(colorMap: colorMap) {
            imageCache[cacheKey] = UIImage(cgImage: cgImage)
        }
    }
    
    @MainActor
    private func pregenerateOverlay(for channel: ChannelData, originalImage: CGImage) async {
        let colorMap = visualizer.currentConfiguration.colorMap
        let cacheKey = "overlay_\(channel.index)_\(colorMap.hashValue)_\(originalImage.hashValue)"
        
        guard imageCache[cacheKey] == nil else { return }
        
        if let overlayImage = createOverlayImage(
            channel: channel,
            originalImage: originalImage,
            colorMap: colorMap,
            alpha: 0.5
        ) {
            imageCache[cacheKey] = UIImage(cgImage: overlayImage)
        }
    }
    
    @MainActor
    private func handlePhotoSelection(item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                selectedImage = uiImage
                await processImage(uiImage)
            }
        } catch {
            showError(message: "Failed to load selected image")
        }
    }
    
    /// Clean up image cache to free memory
    private func cleanupImageCache() {
        // Only keep images from the current result to save memory
        if processedResult != nil {
            // Keep recent cache entries but remove old ones
            let cacheLimit = 10
            if imageCache.count > cacheLimit {
                let sortedKeys = imageCache.keys.sorted()
                let keysToRemove = Array(sortedKeys.dropLast(cacheLimit))
                for key in keysToRemove {
                    imageCache.removeValue(forKey: key)
                }
            }
        } else {
            // No current result, clear everything
            imageCache.removeAll()
        }
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
                await handlePhotoSelection(item: newItem)
            }
        }
        .onDisappear {
            // Clean up caches when view disappears to free memory
            cleanupImageCache()
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
    
    /// Creates an overlay image by blending a channel heatmap with the original image
    private func createOverlayImage(channel: ChannelData, originalImage: CGImage, colorMap: ColorMap, alpha: CGFloat = 0.5) -> CGImage? {
        guard let heatmapImage = channel.toCGImage(colorMap: colorMap) else { return nil }
        
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
            return nil
        }
        
        // Draw original image
        context.draw(originalImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Draw heatmap with alpha
        context.setAlpha(alpha)
        context.draw(heatmapImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return context.makeImage()
    }
}

#endif // os(iOS)