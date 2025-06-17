import SwiftUI
import UNetVisualizerKit

struct ContentView: View {
    var body: some View {
        DemoVisualizationView(modelHandler: createModelHandler())
    }
    
    private func createModelHandler() -> UNetModelHandler {
        do {
            // This is the most important line - creating the model handler
            let modelHandler = try UNetModelHandler(modelName: "SegmentationModel")
            return modelHandler
        } catch {
            fatalError("Failed to load model: \(error)")
        }
    }
}

#Preview {
    ContentView()
}