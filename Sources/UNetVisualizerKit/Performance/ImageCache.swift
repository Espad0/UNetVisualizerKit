import Foundation
import CoreGraphics

/// Thread-safe image cache with LRU eviction
final class ImageCache {
    /// Cache entry
    private struct CacheEntry {
        let value: VisualizationResult
        let size: Int
        let timestamp: Date
        var accessCount: Int = 0
        var lastAccessed: Date
    }
    
    /// Maximum cache size in bytes
    var maxSize: Int = 100 * 1024 * 1024 // 100MB default
    
    /// Thread safety
    private let queue = DispatchQueue(label: "com.unetvisualizer.cache", attributes: .concurrent)
    
    /// Storage
    private var cache: [String: CacheEntry] = [:]
    private var currentSize: Int = 0
    
    /// Statistics
    private(set) var hitCount: Int = 0
    private(set) var missCount: Int = 0
    
    /// Get value from cache
    func get(key: String) -> VisualizationResult? {
        queue.sync {
            guard var entry = cache[key] else {
                missCount += 1
                return nil
            }
            
            // Update access info
            entry.accessCount += 1
            entry.lastAccessed = Date()
            
            // Write back with barrier
            queue.async(flags: .barrier) {
                self.cache[key] = entry
                self.hitCount += 1
            }
            
            return entry.value
        }
    }
    
    /// Set value in cache
    func set(key: String, value: VisualizationResult) {
        let size = estimateSize(of: value)
        
        queue.async(flags: .barrier) {
            // Remove existing entry if present
            if let existing = self.cache[key] {
                self.currentSize -= existing.size
            }
            
            // Add new entry
            let entry = CacheEntry(
                value: value,
                size: size,
                timestamp: Date(),
                lastAccessed: Date()
            )
            
            self.cache[key] = entry
            self.currentSize += size
            
            // Evict if necessary
            self.evictIfNeeded()
        }
    }
    
    /// Clear all cache
    func clear() {
        queue.async(flags: .barrier) {
            self.cache.removeAll()
            self.currentSize = 0
            self.hitCount = 0
            self.missCount = 0
        }
    }
    
    /// Get cache statistics
    func statistics() -> CacheStatistics {
        queue.sync {
            CacheStatistics(
                entryCount: cache.count,
                totalSize: currentSize,
                hitCount: hitCount,
                missCount: missCount,
                hitRate: Double(hitCount) / Double(max(1, hitCount + missCount))
            )
        }
    }
    
    /// Estimate size of visualization result
    private func estimateSize(of result: VisualizationResult) -> Int {
        // Estimate based on image dimensions
        let image = result.visualizedImage
        let bytesPerPixel = 4 // RGBA
        let imageSize = image.width * image.height * bytesPerPixel
        
        // Add overhead for prediction data
        let predictionSize = result.prediction.channels.count * 
            result.prediction.channels[0].values.count * 
            MemoryLayout<Float>.size
        
        return imageSize + predictionSize
    }
    
    /// Evict entries if cache is too large
    private func evictIfNeeded() {
        guard currentSize > maxSize else { return }
        
        // Sort by LRU (least recently used)
        let sortedEntries = cache.sorted { (lhs, rhs) in
            // First by access count (ascending), then by last accessed (ascending)
            if lhs.value.accessCount == rhs.value.accessCount {
                return lhs.value.lastAccessed < rhs.value.lastAccessed
            }
            return lhs.value.accessCount < rhs.value.accessCount
        }
        
        // Evict until under limit
        for (key, entry) in sortedEntries {
            cache.removeValue(forKey: key)
            currentSize -= entry.size
            
            if currentSize <= maxSize * 9 / 10 { // Keep 10% buffer
                break
            }
        }
    }
}

/// Cache statistics
struct CacheStatistics {
    let entryCount: Int
    let totalSize: Int
    let hitCount: Int
    let missCount: Int
    let hitRate: Double
    
    var formattedSize: String {
        let mb = Double(totalSize) / 1024.0 / 1024.0
        return String(format: "%.1f MB", mb)
    }
    
    var formattedHitRate: String {
        return String(format: "%.1f%%", hitRate * 100)
    }
}