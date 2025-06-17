import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Displays the selected image together with an optional overlay when processing.
public struct SelectedImageView: View {
    #if canImport(UIKit)
    let uiImage: UIImage
    #elseif canImport(AppKit)
    let nsImage: NSImage
    #endif
    let isProcessing: Bool

    #if canImport(UIKit)
    public init(uiImage: UIImage, isProcessing: Bool) {
        self.uiImage = uiImage
        self.isProcessing = isProcessing
    }
    #elseif canImport(AppKit)
    public init(nsImage: NSImage, isProcessing: Bool) {
        self.nsImage = nsImage
        self.isProcessing = isProcessing
    }
    #endif

    public var body: some View {
        #if canImport(UIKit)
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
        #elseif canImport(AppKit)
        Image(nsImage: nsImage)
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
        #else
        Image(systemName: "photo")
            .font(.largeTitle)
            .frame(maxHeight: 300)
        #endif
    }
}

/// Placeholder that is shown when no image has been selected yet.
public struct PlaceholderView: View {
    public init() {}
    
    public var body: some View {
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