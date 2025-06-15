import SwiftUI
import PhotosUI
import UNetVisualizerKit
import CoreML
import CoreGraphics

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var processedResult: VisualizationResult?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showFullScreenImage = false
    @State private var selectedChannelIndex: Int? = nil
    @State private var imageCache: [String: UIImage] = [:]
    
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
                    visualizationResultView(result: result)
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
            Label("\(String(format: "%.1f", result.performanceMetrics.currentFPS)) FPS", systemImage: "speedometer")
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
            Text("Combined Visualization")
                .font(.caption)
                .foregroundColor(.secondary)
            
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
            // Handle error silently or show error if needed
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
}


// MARK: - Full Screen Image View
struct FullScreenImageView: View {
    let result: VisualizationResult
    let selectedImage: UIImage?
    let visualizer: UNetVisualizer
    @Binding var currentIndex: Int?
    let isOverlayMode: Bool
    
    @Environment(\.dismiss) private var dismiss
    @State private var displayIndex: Int = 0
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isLoading = false
    @State private var imageCache: [Int: UIImage] = [:]
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    mainContentView(geometry: geometry)
                    
                    loadingOverlay
                    
                    if currentIndex != nil {
                        channelInfoOverlay
                    }
                }
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .gesture(
                // Swipe down to dismiss - only when not zoomed in
                scale <= 1.0 ? DragGesture()
                    .onEnded { value in
                        // Only dismiss if swipe is primarily downward and has sufficient magnitude
                        let verticalDistance = value.translation.height
                        let horizontalDistance = abs(value.translation.width)
                        
                        if verticalDistance > 100 && verticalDistance > horizontalDistance * 2 {
                            dismiss()
                        }
                    } : nil
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                setupInitialIndex()
                preloadAdjacentImages()
            }
            .onChange(of: displayIndex) { newIndex in
                currentIndex = isOverlayMode ? newIndex + 1000 : newIndex
                preloadAdjacentImages()
                
                // Reset zoom when changing channels
                withAnimation(.easeOut(duration: 0.2)) {
                    scale = 1.0
                    lastScale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
        }
    }
    
    
    @ViewBuilder
    private var channelSwipeView: some View {
        TabView(selection: $displayIndex) {
            ForEach(0..<result.prediction.channels.count, id: \.self) { index in
                GeometryReader { geometry in
                    channelImageView(for: index, geometry: geometry)
                }
                .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        if isLoading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
        }
    }
    
    @ViewBuilder
    private var channelInfoOverlay: some View {
        VStack {
            HStack {
                Text("Channel \(displayIndex)")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            
            Spacer()
            
            pageIndicator
        }
    }
    
    @ViewBuilder
    private var pageIndicator: some View {
        HStack(spacing: 8) {
            let maxIndicators = min(result.prediction.channels.count, 10)
            ForEach(0..<maxIndicators, id: \.self) { index in
                Circle()
                    .fill(displayIndex == index ? Color.white : Color.white.opacity(0.5))
                    .frame(width: 8, height: 8)
            }
            
            if result.prediction.channels.count > 10 {
                Text("\(displayIndex + 1)/\(result.prediction.channels.count)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.leading, 4)
            }
        }
        .padding()
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
        .padding(.bottom, 20)
    }
    
    @ViewBuilder
    private func mainContentView(geometry: GeometryProxy) -> some View {
        if currentIndex == nil {
            combinedVisualizationView(geometry: geometry)
        } else {
            channelSwipeView
        }
    }
    
    @ViewBuilder
    private func combinedVisualizationView(geometry: GeometryProxy) -> some View {
        Image(uiImage: UIImage(cgImage: result.visualizedImage))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = lastScale * value
                    }
                    .onEnded { value in
                        lastScale = scale
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
            .simultaneousGesture(
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
    
    @ViewBuilder
    private func channelImageView(for index: Int, geometry: GeometryProxy) -> some View {
        ZStack {
            Color.clear
            
            if let image = getImage(for: index) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { value in
                                lastScale = scale
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                    .simultaneousGesture(
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                    .allowsHitTesting(scale > 1.0) // Only allow drag gestures when zoomed
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .onAppear {
                        loadImage(for: index)
                    }
            }
        }
    }
    
    private func setupInitialIndex() {
        if let currentIndex = currentIndex {
            displayIndex = isOverlayMode ? currentIndex - 1000 : currentIndex
        } else {
            displayIndex = 0
        }
    }
    
    private func getImage(for index: Int) -> UIImage? {
        // Check cache first
        if let cachedImage = imageCache[index] {
            return cachedImage
        }
        
        // Generate image
        loadImage(for: index)
        return nil
    }
    
    private func loadImage(for index: Int) {
        guard index >= 0 && index < result.prediction.channels.count else { return }
        
        let channel = result.prediction.channels[index]
        
        Task { @MainActor in
            var image: UIImage?
            
            if isOverlayMode {
                // Generate overlay image
                if let selectedImage = selectedImage,
                   let cgImage = selectedImage.cgImage,
                   let overlayImage = createOverlayImage(
                    channel: channel,
                    originalImage: cgImage,
                    colorMap: visualizer.currentConfiguration.colorMap,
                    alpha: 0.5
                   ) {
                    image = UIImage(cgImage: overlayImage)
                }
            } else {
                // Generate heatmap image
                if let cgImage = channel.toCGImage(colorMap: visualizer.currentConfiguration.colorMap) {
                    image = UIImage(cgImage: cgImage)
                }
            }
            
            if let image = image {
                imageCache[index] = image
            }
        }
    }
    
    private func preloadAdjacentImages() {
        // Preload current, previous, and next images
        let indicesToLoad = [displayIndex - 1, displayIndex, displayIndex + 1]
        
        for index in indicesToLoad {
            if index >= 0 && index < result.prediction.channels.count && imageCache[index] == nil {
                loadImage(for: index)
            }
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

// MARK: - Overlay Helper
extension ContentView {
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

#Preview {
    ContentView()
}
