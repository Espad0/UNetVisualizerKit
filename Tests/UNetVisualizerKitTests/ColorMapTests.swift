import XCTest
@testable import UNetVisualizerKit

final class ColorMapTests: XCTestCase {
    
    func testGrayscaleColorMap() {
        let colorMap = ColorMap.grayscale
        
        // Test edge cases
        XCTAssertEqual(colorMap.color(for: 0).r, 0)
        XCTAssertEqual(colorMap.color(for: 0).g, 0)
        XCTAssertEqual(colorMap.color(for: 0).b, 0)
        
        XCTAssertEqual(colorMap.color(for: 1).r, 255)
        XCTAssertEqual(colorMap.color(for: 1).g, 255)
        XCTAssertEqual(colorMap.color(for: 1).b, 255)
        
        // Test middle value
        let midColor = colorMap.color(for: 0.5)
        XCTAssertEqual(midColor.r, 127)
        XCTAssertEqual(midColor.g, 127)
        XCTAssertEqual(midColor.b, 127)
        
        // Test clamping
        XCTAssertEqual(colorMap.color(for: -0.5), colorMap.color(for: 0))
        XCTAssertEqual(colorMap.color(for: 1.5), colorMap.color(for: 1))
    }
    
    func testHeatmapColorMap() {
        let colorMap = ColorMap.heatmap
        
        // Test key points in heatmap
        // 0.0 should be blue
        let blue = colorMap.color(for: 0)
        XCTAssertEqual(blue.r, 0)
        XCTAssertEqual(blue.b, 255)
        
        // 0.5 should be greenish
        let green = colorMap.color(for: 0.5)
        XCTAssertGreaterThan(green.g, 200)
        
        // 1.0 should be red
        let red = colorMap.color(for: 1)
        XCTAssertEqual(red.r, 255)
        XCTAssertEqual(red.b, 0)
    }
    
    func testCustomColorMap() {
        let customColors: [(Float, UNetVisualizerKit.RGBColor)] = [
            (0.0, UNetVisualizerKit.RGBColor(255, 0, 0)),    // Red at 0
            (0.5, UNetVisualizerKit.RGBColor(0, 255, 0)),    // Green at 0.5
            (1.0, UNetVisualizerKit.RGBColor(0, 0, 255))     // Blue at 1
        ]
        
        let colorMap = ColorMap.custom(customColors)
        
        // Test exact points
        XCTAssertEqual(colorMap.color(for: 0).r, 255)
        XCTAssertEqual(colorMap.color(for: 0).g, 0)
        
        XCTAssertEqual(colorMap.color(for: 0.5).g, 255)
        
        XCTAssertEqual(colorMap.color(for: 1).b, 255)
        
        // Test interpolation
        let quarter = colorMap.color(for: 0.25)
        XCTAssertGreaterThan(quarter.r, 100)
        XCTAssertGreaterThan(quarter.g, 100)
        XCTAssertEqual(quarter.b, 0)
    }
    
    func testViridisColorMap() {
        let colorMap = ColorMap.viridis
        
        // Viridis should go from purple to yellow
        let start = colorMap.color(for: 0)
        let end = colorMap.color(for: 1)
        
        // Start should be purplish
        XCTAssertLessThan(start.r, 100)
        XCTAssertLessThan(start.g, 50)
        XCTAssertGreaterThan(start.b, 50)
        
        // End should be yellowish
        XCTAssertGreaterThan(end.r, 200)
        XCTAssertGreaterThan(end.g, 200)
        XCTAssertLessThan(end.b, 100)
    }
    
    func testColorMapInterpolation() {
        let colors: [(Float, UNetVisualizerKit.RGBColor)] = [
            (0.0, UNetVisualizerKit.RGBColor(0, 0, 0)),
            (1.0, UNetVisualizerKit.RGBColor(255, 255, 255))
        ]
        
        let colorMap = ColorMap.custom(colors)
        
        // Test various interpolation points
        for i in 0...10 {
            let value = Float(i) / 10.0
            let color = colorMap.color(for: value)
            let expected = UInt8(value * 255)
            
            XCTAssertEqual(color.r, expected, accuracy: 1)
            XCTAssertEqual(color.g, expected, accuracy: 1)
            XCTAssertEqual(color.b, expected, accuracy: 1)
        }
    }
    
    func testDivergingColorMap() {
        let diverging = ColorMap.diverging(
            negativeColor: UNetVisualizerKit.RGBColor(0, 0, 255),
            neutralColor: UNetVisualizerKit.RGBColor(255, 255, 255),
            positiveColor: UNetVisualizerKit.RGBColor(255, 0, 0)
        )
        
        // Test key points
        XCTAssertEqual(diverging.color(for: 0).b, 255)
        XCTAssertEqual(diverging.color(for: 0.5).r, 255)
        XCTAssertEqual(diverging.color(for: 0.5).g, 255)
        XCTAssertEqual(diverging.color(for: 0.5).b, 255)
        XCTAssertEqual(diverging.color(for: 1).r, 255)
    }
    
    func testDiscreteColorMap() {
        let colors = [
            UNetVisualizerKit.RGBColor(255, 0, 0),
            UNetVisualizerKit.RGBColor(0, 255, 0),
            UNetVisualizerKit.RGBColor(0, 0, 255)
        ]
        
        let discrete = ColorMap.discrete(colors: colors)
        
        // Should map evenly across the range
        XCTAssertEqual(discrete.color(for: 0).r, 255)
        XCTAssertEqual(discrete.color(for: 0.5).g, 255)
        XCTAssertEqual(discrete.color(for: 1).b, 255)
    }
    
    func testColorMapPerformance() {
        let colorMap = ColorMap.viridis
        
        measure {
            // Generate 1000 colors
            for i in 0..<1000 {
                let value = Float(i) / 1000.0
                _ = colorMap.color(for: value)
            }
        }
    }
}

