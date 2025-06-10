import XCTest
@testable import UNetVisualizerKit

final class PerformanceMonitorTests: XCTestCase {
    
    var monitor: PerformanceMonitor!
    
    override func setUp() {
        super.setUp()
        monitor = PerformanceMonitor()
    }
    
    override func tearDown() {
        monitor = nil
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertEqual(monitor.currentFPS, 0)
        XCTAssertEqual(monitor.averageInferenceTime, 0)
        XCTAssertGreaterThan(monitor.memoryUsageMB, 0) // Should have some memory usage
    }
    
    func testRecordingFrames() {
        // Record multiple frames
        for _ in 0..<10 {
            monitor.recordFrame()
            Thread.sleep(forTimeInterval: 0.01) // 10ms between frames
        }
        
        // Wait for metrics update
        let expectation = XCTestExpectation(description: "Metrics updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertGreaterThan(self.monitor.currentFPS, 0)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testRecordingInferenceTime() {
        let inferenceTimes: [Double] = [10.5, 12.3, 11.8, 13.2, 10.9]
        
        for time in inferenceTimes {
            monitor.recordInference(time: time)
        }
        
        // Wait for metrics update
        let expectation = XCTestExpectation(description: "Inference time updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            XCTAssertGreaterThan(self.monitor.averageInferenceTime, 0)
            
            // Check if average is reasonable
            let expectedAverage = inferenceTimes.reduce(0, +) / Double(inferenceTimes.count)
            XCTAssertEqual(self.monitor.averageInferenceTime, expectedAverage, accuracy: 0.1)
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testMetricsSnapshot() {
        // Record some data
        for i in 0..<5 {
            monitor.recordInference(time: Double(10 + i))
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        let metrics = monitor.currentMetrics()
        
        XCTAssertNotNil(metrics)
        XCTAssertGreaterThanOrEqual(metrics.totalFramesProcessed, 5)
        XCTAssertGreaterThan(metrics.memoryUsageMB, 0)
        XCTAssertEqual(metrics.minInferenceTime, 10, accuracy: 0.1)
        XCTAssertEqual(metrics.maxInferenceTime, 14, accuracy: 0.1)
    }
    
    func testReset() {
        // Record some data
        for _ in 0..<10 {
            monitor.recordFrame()
            monitor.recordInference(time: 15.0)
        }
        
        // Reset
        monitor.reset()
        
        // Verify reset
        let expectation = XCTestExpectation(description: "Metrics reset")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.monitor.currentFPS, 0)
            XCTAssertEqual(self.monitor.averageInferenceTime, 0)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 0.5)
    }
    
    func testPerformanceAlertLevels() {
        let targetFPS: Double = 30
        
        XCTAssertEqual(PerformanceAlert.level(for: 30, target: targetFPS), .none)
        XCTAssertEqual(PerformanceAlert.level(for: 27, target: targetFPS), .none) // 90%
        XCTAssertEqual(PerformanceAlert.level(for: 21, target: targetFPS), .low)   // 70%
        XCTAssertEqual(PerformanceAlert.level(for: 15, target: targetFPS), .medium) // 50%
        XCTAssertEqual(PerformanceAlert.level(for: 10, target: targetFPS), .high)   // 33%
    }
    
    func testWindowSizeConfiguration() {
        var config = PerformanceMonitor.Configuration()
        config.windowSize = 5
        
        let customMonitor = PerformanceMonitor(configuration: config)
        
        // Record more than window size
        for i in 0..<10 {
            customMonitor.recordInference(time: Double(i))
        }
        
        let metrics = customMonitor.currentMetrics()
        
        // Should only consider last 5 values
        XCTAssertEqual(metrics.minInferenceTime, 5, accuracy: 0.1)
        XCTAssertEqual(metrics.maxInferenceTime, 9, accuracy: 0.1)
    }
    
    func testConcurrentAccess() {
        let expectation = XCTestExpectation(description: "Concurrent access completed")
        let iterations = 100
        
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            monitor.recordFrame()
            monitor.recordInference(time: Double(index))
            
            if index == iterations - 1 {
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        let metrics = monitor.currentMetrics()
        XCTAssertEqual(metrics.totalFramesProcessed, iterations)
    }
    
    func testMemoryUsageTracking() {
        let initialMemory = monitor.memoryUsageMB
        XCTAssertGreaterThan(initialMemory, 0)
        
        // Allocate some memory
        var largeArray = Array(repeating: 0, count: 1_000_000)
        largeArray[0] = 1 // Use it to prevent optimization
        
        // Check if memory usage increased
        let expectation = XCTestExpectation(description: "Memory usage updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let currentMemory = self.monitor.memoryUsageMB
            XCTAssertGreaterThanOrEqual(currentMemory, initialMemory)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        _ = largeArray // Keep reference until end
    }
    
    func testPerformanceReport() {
        // Record some data
        for i in 0..<5 {
            monitor.recordInference(time: Double(10 + i * 2))
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        let metrics = monitor.currentMetrics()
        let report = metrics.report
        
        XCTAssertTrue(report.contains("Performance Report"))
        XCTAssertTrue(report.contains("FPS:"))
        XCTAssertTrue(report.contains("Inference Time:"))
        XCTAssertTrue(report.contains("Total Frames:"))
        XCTAssertTrue(report.contains("Memory Usage:"))
    }
}

// MARK: - Helpers
private extension XCTestCase {
    func wait(for expectations: [XCTestExpectation], timeout: TimeInterval) {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
        wait(for: expectations, timeout: timeout)
        #endif
    }
}