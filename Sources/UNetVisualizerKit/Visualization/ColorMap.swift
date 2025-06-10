import Foundation
import CoreGraphics

/// Color representation for visualization
public struct RGBColor: Hashable, Equatable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    
    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// Predefined color maps for visualization
public enum ColorMap: Hashable {
    case grayscale
    case heatmap
    case viridis
    case plasma
    case inferno
    case magma
    case rainbow
    case custom([(Float, RGBColor)])
    
    /// Get color for normalized value (0-1)
    public func color(for value: Float) -> RGBColor {
        let clampedValue = max(0, min(1, value))
        
        switch self {
        case .grayscale:
            let gray = UInt8(clampedValue * 255)
            return RGBColor(gray, gray, gray)
            
        case .heatmap:
            return heatmapColor(clampedValue)
            
        case .viridis:
            return viridisColor(clampedValue)
            
        case .plasma:
            return plasmaColor(clampedValue)
            
        case .inferno:
            return infernoColor(clampedValue)
            
        case .magma:
            return magmaColor(clampedValue)
            
        case .rainbow:
            return rainbowColor(clampedValue)
            
        case .custom(let colorStops):
            return interpolateColor(clampedValue, colorStops: colorStops)
        }
    }
    
    /// Classic heatmap (blue -> green -> yellow -> red)
    private func heatmapColor(_ value: Float) -> RGBColor {
        if value < 0.25 {
            // Blue to cyan
            let t = value * 4
            return RGBColor(0, UInt8(t * 255), 255)
        } else if value < 0.5 {
            // Cyan to green
            let t = (value - 0.25) * 4
            return RGBColor(0, 255, UInt8((1 - t) * 255))
        } else if value < 0.75 {
            // Green to yellow
            let t = (value - 0.5) * 4
            return RGBColor(UInt8(t * 255), 255, 0)
        } else {
            // Yellow to red
            let t = (value - 0.75) * 4
            return RGBColor(255, UInt8((1 - t) * 255), 0)
        }
    }
    
    /// Viridis colormap (matplotlib)
    private func viridisColor(_ value: Float) -> RGBColor {
        let colors: [(Float, RGBColor)] = [
            (0.0, RGBColor(68, 1, 84)),
            (0.25, RGBColor(59, 82, 139)),
            (0.5, RGBColor(33, 145, 140)),
            (0.75, RGBColor(94, 201, 98)),
            (1.0, RGBColor(253, 231, 37))
        ]
        return interpolateColor(value, colorStops: colors)
    }
    
    /// Plasma colormap (matplotlib)
    private func plasmaColor(_ value: Float) -> RGBColor {
        let colors: [(Float, RGBColor)] = [
            (0.0, RGBColor(13, 8, 135)),
            (0.25, RGBColor(126, 3, 168)),
            (0.5, RGBColor(204, 71, 120)),
            (0.75, RGBColor(248, 149, 64)),
            (1.0, RGBColor(240, 249, 33))
        ]
        return interpolateColor(value, colorStops: colors)
    }
    
    /// Inferno colormap (matplotlib)
    private func infernoColor(_ value: Float) -> RGBColor {
        let colors: [(Float, RGBColor)] = [
            (0.0, RGBColor(0, 0, 4)),
            (0.25, RGBColor(87, 16, 110)),
            (0.5, RGBColor(188, 55, 84)),
            (0.75, RGBColor(249, 142, 9)),
            (1.0, RGBColor(252, 255, 164))
        ]
        return interpolateColor(value, colorStops: colors)
    }
    
    /// Magma colormap (matplotlib)
    private func magmaColor(_ value: Float) -> RGBColor {
        let colors: [(Float, RGBColor)] = [
            (0.0, RGBColor(0, 0, 4)),
            (0.25, RGBColor(81, 18, 124)),
            (0.5, RGBColor(183, 55, 121)),
            (0.75, RGBColor(251, 136, 97)),
            (1.0, RGBColor(252, 253, 191))
        ]
        return interpolateColor(value, colorStops: colors)
    }
    
    /// Rainbow/HSV colormap
    private func rainbowColor(_ value: Float) -> RGBColor {
        let hue = value * 300 // 0 to 300 degrees (red to magenta)
        let saturation: Float = 1.0
        let brightness: Float = 1.0
        
        // HSV to RGB conversion
        let c = brightness * saturation
        let x = c * (1 - abs(fmodf(hue / 60, 2) - 1))
        let m = brightness - c
        
        var r: Float = 0, g: Float = 0, b: Float = 0
        
        if hue < 60 {
            r = c; g = x; b = 0
        } else if hue < 120 {
            r = x; g = c; b = 0
        } else if hue < 180 {
            r = 0; g = c; b = x
        } else if hue < 240 {
            r = 0; g = x; b = c
        } else if hue < 300 {
            r = x; g = 0; b = c
        } else {
            r = c; g = 0; b = x
        }
        
        return RGBColor(
            UInt8((r + m) * 255),
            UInt8((g + m) * 255),
            UInt8((b + m) * 255)
        )
    }
    
    /// Interpolate between color stops
    private func interpolateColor(_ value: Float, colorStops: [(Float, RGBColor)]) -> RGBColor {
        guard !colorStops.isEmpty else { return RGBColor(0, 0, 0) }
        
        // Find surrounding color stops
        var lowerStop = colorStops[0]
        var upperStop = colorStops[colorStops.count - 1]
        
        for i in 0..<colorStops.count - 1 {
            if value >= colorStops[i].0 && value <= colorStops[i + 1].0 {
                lowerStop = colorStops[i]
                upperStop = colorStops[i + 1]
                break
            }
        }
        
        // Handle edge cases
        if value <= lowerStop.0 { return lowerStop.1 }
        if value >= upperStop.0 { return upperStop.1 }
        
        // Linear interpolation
        let t = (value - lowerStop.0) / (upperStop.0 - lowerStop.0)
        
        let r = Float(lowerStop.1.r) + t * (Float(upperStop.1.r) - Float(lowerStop.1.r))
        let g = Float(lowerStop.1.g) + t * (Float(upperStop.1.g) - Float(lowerStop.1.g))
        let b = Float(lowerStop.1.b) + t * (Float(upperStop.1.b) - Float(lowerStop.1.b))
        
        return RGBColor(UInt8(r), UInt8(g), UInt8(b))
    }
}

/// Extension for creating custom color maps
public extension ColorMap {
    /// Create a diverging colormap centered at 0.5
    static func diverging(negativeColor: RGBColor, neutralColor: RGBColor, positiveColor: RGBColor) -> ColorMap {
        return .custom([
            (Float(0.0), negativeColor),
            (Float(0.5), neutralColor),
            (Float(1.0), positiveColor)
        ])
    }
    
    /// Create a discrete colormap with specific number of levels
    static func discrete(colors: [RGBColor]) -> ColorMap {
        guard !colors.isEmpty else { return .grayscale }
        
        var colorStops: [(Float, RGBColor)] = []
        for (index, color) in colors.enumerated() {
            let position = Float(index) / Float(colors.count - 1)
            colorStops.append((position, color))
        }
        
        return .custom(colorStops)
    }
}

/// Equatable conformance for ColorMap
extension ColorMap: Equatable {
    public static func == (lhs: ColorMap, rhs: ColorMap) -> Bool {
        switch (lhs, rhs) {
        case (.grayscale, .grayscale),
             (.heatmap, .heatmap),
             (.viridis, .viridis),
             (.plasma, .plasma),
             (.inferno, .inferno),
             (.magma, .magma),
             (.rainbow, .rainbow):
            return true
        case let (.custom(lhsStops), .custom(rhsStops)):
            guard lhsStops.count == rhsStops.count else { return false }
            for (i, (lhsPos, lhsColor)) in lhsStops.enumerated() {
                let (rhsPos, rhsColor) = rhsStops[i]
                if lhsPos != rhsPos || lhsColor != rhsColor {
                    return false
                }
            }
            return true
        default:
            return false
        }
    }
}

/// Hashable conformance for ColorMap
extension ColorMap {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .grayscale:
            hasher.combine(0)
        case .heatmap:
            hasher.combine(1)
        case .viridis:
            hasher.combine(2)
        case .plasma:
            hasher.combine(3)
        case .inferno:
            hasher.combine(4)
        case .magma:
            hasher.combine(5)
        case .rainbow:
            hasher.combine(6)
        case .custom(let stops):
            hasher.combine(7)
            hasher.combine(stops.count)
            for (position, color) in stops {
                hasher.combine(position)
                hasher.combine(color)
            }
        }
    }
}