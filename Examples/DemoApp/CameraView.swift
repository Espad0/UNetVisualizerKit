import SwiftUI
import AVFoundation
import UNetVisualizerKit
import CoreML
import Vision

struct CameraView: View {
    @StateObject private var camera = CameraManager()
    @State private var processedResult: VisualizationResult?
    @State private var isProcessing = false
    @State private var delegateHandler: CameraDelegateHandler?
    @State private var lastCapturedImage: CGImage?
    @State private var imageCache: [String: UIImage] = [:]
    @Environment(\.dismiss) private var dismiss
    
    let visualizer: UNetVisualizer
    
    init(visualizer: UNetVisualizer) {
        self.visualizer = visualizer
    }
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(camera: camera)
                .ignoresSafeArea()
            
            // Visualization grid overlay
            if let result = processedResult {
                visualizationGridOverlay(result: result)
            }
            
            // Controls overlay
            VStack {
                HStack {
                    // Back button
                    Button(action: {
                        camera.stopSession()
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .padding()
                    
                    Spacer()
                }
                
                Spacer()
                
                // Bottom controls
                HStack {
                    // Processing indicator
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    
                    Spacer()
                    
                    // Pause/Resume button
                    Button(action: {
                        if camera.isPaused {
                            camera.resumeProcessing()
                        } else {
                            camera.pauseProcessing()
                        }
                    }) {
                        Image(systemName: camera.isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                }
                .padding()
                .padding(.bottom)
            }
        }
        .onAppear {
            let handler = CameraDelegateHandler { [weak camera] sampleBuffer in
                handleCameraFrame(sampleBuffer)
            }
            delegateHandler = handler
            camera.delegate = handler
            camera.checkPermission()
        }
        .onDisappear {
            camera.stopSession()
        }
    }
}

// MARK: - Camera Manager
class CameraManager: NSObject, ObservableObject {
    @Published var isPaused = false
    @Published var permissionGranted = false
    
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let processingQueue = DispatchQueue(label: "camera.processing.queue", qos: .userInitiated)
    private var videoOutput = AVCaptureVideoDataOutput()
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var frameCount = 0
    
    weak var delegate: CameraProcessingDelegate?
    
    override init() {
        super.init()
        setupSession()
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    if granted {
                        self?.startSession()
                    }
                }
            }
        default:
            permissionGranted = false
        }
    }
    
    private func setupSession() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }
    
    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720 // Lower resolution for better performance
        
        // Add video input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCameraPosition) else {
            session.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("Failed to create camera input: \(error)")
            session.commitConfiguration()
            return
        }
        
        // Configure video output
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        // Set video orientation
        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
        }
        
        session.commitConfiguration()
    }
    
    func startSession() {
        sessionQueue.async { [weak self] in
            if !(self?.session.isRunning ?? false) {
                self?.session.startRunning()
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            if self?.session.isRunning ?? false {
                self?.session.stopRunning()
            }
        }
    }
    
    func pauseProcessing() {
        isPaused = true
    }
    
    func resumeProcessing() {
        isPaused = false
    }
    
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isPaused else { return }
        
        // Throttle processing - process every 15th frame for better performance with visualizations
        frameCount += 1
        guard frameCount % 15 == 0 else { return }
        
        delegate?.processCameraFrame(sampleBuffer)
    }
}

// MARK: - Camera Processing Delegate
protocol CameraProcessingDelegate: AnyObject {
    func processCameraFrame(_ sampleBuffer: CMSampleBuffer)
}

// MARK: - Camera Delegate Handler
class CameraDelegateHandler: CameraProcessingDelegate {
    private let frameHandler: (CMSampleBuffer) -> Void
    
    init(frameHandler: @escaping (CMSampleBuffer) -> Void) {
        self.frameHandler = frameHandler
    }
    
    func processCameraFrame(_ sampleBuffer: CMSampleBuffer) {
        frameHandler(sampleBuffer)
    }
}

// MARK: - Camera Frame Processing
extension CameraView {
    func handleCameraFrame(_ sampleBuffer: CMSampleBuffer) {
        guard !isProcessing else { return }
        
        // Convert CMSampleBuffer to CGImage
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let cgImage = pixelBuffer.toCGImage() else { return }
        
        Task { @MainActor in
            isProcessing = true
            
            do {
                let result = try await visualizer.process(cgImage)
                lastCapturedImage = cgImage
                processedResult = result
                
                // Clear cache when new result is processed
                imageCache.removeAll()
            } catch {
                print("Failed to process frame: \(error)")
            }
            
            isProcessing = false
        }
    }
    
    // MARK: - Visualization Grid Components
    @ViewBuilder
    private func visualizationGridOverlay(result: VisualizationResult) -> some View {
        VStack {
            Spacer()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Performance metrics
                    HStack {
                        Spacer()
                        Label("\(String(format: "%.1f", result.prediction.inferenceTime))ms", systemImage: "timer")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                    }
                    .padding(.horizontal)
                    
                    // Channel heatmaps
                    channelHeatmapsSection(result: result)
                    
                    // Channel overlays
                    if let cgImage = lastCapturedImage {
                        channelOverlaysSection(result: result, originalImage: cgImage)
                    }
                }
                .padding(.bottom, 100) // Space for bottom controls
            }
            .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
        }
    }
    
    @ViewBuilder
    private func channelHeatmapsSection(result: VisualizationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Channel Heatmaps (\(result.prediction.channels.count) channels)")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(result.prediction.channels, id: \.index) { channel in
                        channelHeatmapItem(channel: channel)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    private func channelOverlaysSection(result: VisualizationResult, originalImage: CGImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Channel Overlays")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(result.prediction.channels, id: \.index) { channel in
                        channelOverlayItem(channel: channel, originalImage: originalImage)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    
    @ViewBuilder
    private func channelHeatmapItem(channel: ChannelData) -> some View {
        VStack(spacing: 2) {
            Text("Ch \(channel.index)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            if let heatmapImage = getCachedHeatmapImage(for: channel, colorMap: visualizer.currentConfiguration.colorMap) {
                Image(uiImage: heatmapImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }
    
    @ViewBuilder
    private func channelOverlayItem(channel: ChannelData, originalImage: CGImage) -> some View {
        VStack(spacing: 2) {
            Text("Ch \(channel.index)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            if let overlayImage = getCachedOverlayImage(for: channel, originalImage: originalImage, colorMap: visualizer.currentConfiguration.colorMap) {
                Image(uiImage: overlayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }
    
    // MARK: - Cache Helpers
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

// MARK: - Camera Preview View
struct CameraPreviewView: UIViewRepresentable {
    let camera: CameraManager
    
    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}


// MARK: - CVPixelBuffer Extension
extension CVPixelBuffer {
    func toCGImage() -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: self)
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}