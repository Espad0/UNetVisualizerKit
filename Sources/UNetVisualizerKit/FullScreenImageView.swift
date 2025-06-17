import SwiftUI
import CoreGraphics

#if os(iOS)
import UIKit

public struct FullScreenImageView: View {
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
    
    public init(result: VisualizationResult, selectedImage: UIImage?, visualizer: UNetVisualizer, currentIndex: Binding<Int?>, isOverlayMode: Bool) {
        self.result = result
        self.selectedImage = selectedImage
        self.visualizer = visualizer
        self._currentIndex = currentIndex
        self.isOverlayMode = isOverlayMode
    }
    
    public var body: some View {
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

#endif // os(iOS)