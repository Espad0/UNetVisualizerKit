import Foundation
import Combine
import os.log

/// Monitors and tracks performance metrics for U-Net visualization
public final class PerformanceMonitor: ObservableObject {
    
    /// Performance metrics snapshot
    public struct PerformanceMetrics {
        public let currentFPS: Double
        public let averageFPS: Double
        public let minFPS: Double
        public let maxFPS: Double
        public let averageInferenceTime: Double
        public let minInferenceTime: Double
        public let maxInferenceTime: Double
        public let totalFramesProcessed: Int
        public let memoryUsageMB: Double
        public let timestamp: Date
    }
    
    /// Published properties for real-time monitoring
    @Published public private(set) var currentFPS: Double = 0
    @Published public private(set) var averageInferenceTime: Double = 0
    @Published public private(set) var memoryUsageMB: Double = 0
    
    /// Configuration
    public struct Configuration {
        /// Window size for moving averages
        public var windowSize: Int = 30
        
        /// Update interval in seconds
        public var updateInterval: TimeInterval = 0.5
        
        /// Whether to log performance warnings
        public var enableWarnings: Bool = true
        
        /// FPS threshold for warnings
        public var warningFPSThreshold: Double = 20
        
        public init() {}
    }
    
    private var configuration: Configuration
    private let logger = Logger(subsystem: "com.unetvisualizer", category: "Performance")
    
    /// Thread-safe storage for metrics
    private let metricsQueue = DispatchQueue(label: "com.unetvisualizer.metrics", attributes: .concurrent)
    private var frameTimestamps: [Date] = []
    private var inferenceTimes: [Double] = []
    private var totalFramesProcessed: Int = 0
    
    /// Timer for periodic updates
    private var updateTimer: Timer?
    
    /// Memory tracking
    private var initialMemoryFootprint: Double = 0
    
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.initialMemoryFootprint = getCurrentMemoryUsage()
        
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    /// Configure the monitor
    public func configure(_ block: (inout Configuration) -> Void) {
        block(&configuration)
    }
    
    /// Record a frame processing event
    public func recordFrame() {
        metricsQueue.async(flags: .barrier) {
            self.frameTimestamps.append(Date())
            self.totalFramesProcessed += 1
            
            // Trim old timestamps
            let cutoff = Date().addingTimeInterval(-Double(self.configuration.windowSize))
            self.frameTimestamps.removeAll { $0 < cutoff }
        }
    }
    
    /// Record inference time
    public func recordInference(time: Double) {
        metricsQueue.async(flags: .barrier) {
            self.inferenceTimes.append(time)
            
            // Keep only recent measurements
            if self.inferenceTimes.count > self.configuration.windowSize {
                self.inferenceTimes.removeFirst()
            }
        }
        
        // Also record as a frame
        recordFrame()
    }
    
    /// Get current performance metrics
    public func currentMetrics() -> PerformanceMetrics {
        metricsQueue.sync {
            let fps = calculateFPS()
            let avgInference = inferenceTimes.isEmpty ? 0 : inferenceTimes.reduce(0, +) / Double(inferenceTimes.count)
            
            return PerformanceMetrics(
                currentFPS: fps.current,
                averageFPS: fps.average,
                minFPS: fps.min,
                maxFPS: fps.max,
                averageInferenceTime: avgInference,
                minInferenceTime: inferenceTimes.min() ?? 0,
                maxInferenceTime: inferenceTimes.max() ?? 0,
                totalFramesProcessed: totalFramesProcessed,
                memoryUsageMB: memoryUsageMB,
                timestamp: Date()
            )
        }
    }
    
    /// Reset all metrics
    public func reset() {
        metricsQueue.async(flags: .barrier) {
            self.frameTimestamps.removeAll()
            self.inferenceTimes.removeAll()
            self.totalFramesProcessed = 0
        }
        
        DispatchQueue.main.async {
            self.currentFPS = 0
            self.averageInferenceTime = 0
            self.memoryUsageMB = 0
        }
    }
    
    /// Start monitoring
    private func startMonitoring() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: configuration.updateInterval, repeats: true) { _ in
            self.updateMetrics()
        }
    }
    
    /// Stop monitoring
    private func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    /// Update published metrics
    private func updateMetrics() {
        let metrics = currentMetrics()
        
        DispatchQueue.main.async {
            self.currentFPS = metrics.currentFPS
            self.averageInferenceTime = metrics.averageInferenceTime
            self.memoryUsageMB = self.getCurrentMemoryUsage()
        }
        
        // Log warnings if needed
        if configuration.enableWarnings && metrics.currentFPS < configuration.warningFPSThreshold && metrics.currentFPS > 0 {
            logger.warning("Low FPS detected: \(metrics.currentFPS, format: .fixed(precision: 1)) FPS")
        }
    }
    
    /// Calculate FPS metrics
    private func calculateFPS() -> (current: Double, average: Double, min: Double, max: Double) {
        guard !frameTimestamps.isEmpty else {
            return (0, 0, 0, 0)
        }
        
        let now = Date()
        let recentTimestamps = frameTimestamps.filter { now.timeIntervalSince($0) <= 1.0 }
        let currentFPS = Double(recentTimestamps.count)
        
        // Calculate average over window
        var intervalFPS: [Double] = []
        for i in 1..<frameTimestamps.count {
            let interval = frameTimestamps[i].timeIntervalSince(frameTimestamps[i-1])
            if interval > 0 {
                intervalFPS.append(1.0 / interval)
            }
        }
        
        let averageFPS = intervalFPS.isEmpty ? 0 : intervalFPS.reduce(0, +) / Double(intervalFPS.count)
        let minFPS = intervalFPS.min() ?? 0
        let maxFPS = intervalFPS.max() ?? 0
        
        return (currentFPS, averageFPS, minFPS, maxFPS)
    }
    
    /// Get current memory usage in MB
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        }
        
        return 0
    }
}

/// Performance alert levels
public enum PerformanceAlert {
    case none
    case low
    case medium
    case high
    
    public var color: String {
        switch self {
        case .none: return "green"
        case .low: return "yellow"
        case .medium: return "orange"
        case .high: return "red"
        }
    }
    
    public static func level(for fps: Double, target: Double) -> PerformanceAlert {
        let ratio = fps / target
        
        if ratio >= 0.9 { return .none }
        if ratio >= 0.7 { return .low }
        if ratio >= 0.5 { return .medium }
        return .high
    }
}

/// Extension for formatting performance metrics
public extension PerformanceMonitor.PerformanceMetrics {
    /// Generate a performance report string
    var report: String {
        """
        Performance Report - \(timestamp.formatted())
        ================================================
        FPS: \(String(format: "%.1f", currentFPS)) (avg: \(String(format: "%.1f", averageFPS)))
        Range: \(String(format: "%.1f", minFPS)) - \(String(format: "%.1f", maxFPS))
        
        Inference Time: \(String(format: "%.1f", averageInferenceTime))ms
        Range: \(String(format: "%.1f", minInferenceTime)) - \(String(format: "%.1f", maxInferenceTime))ms
        
        Total Frames: \(totalFramesProcessed)
        Memory Usage: \(String(format: "%.1f", memoryUsageMB))MB
        ================================================
        """
    }
    
    /// Check if performance is within acceptable range
    func isPerformanceAcceptable(targetFPS: Double) -> Bool {
        return currentFPS >= targetFPS * 0.9
    }
}