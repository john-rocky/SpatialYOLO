import SwiftUI
import SpatialYOLO

struct ContentView: View {

    @StateObject private var manager = ARSessionManager()

    var body: some View {
        ZStack {
            switch manager.state {
            case .idle, .loading:
                ProgressView("Loading model...")

            case .running:
                if let pipeline = manager.pipeline {
                    SpatialYOLOView(pipeline: pipeline, session: manager.session)
                        .ignoresSafeArea()
                }

            case .error(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .task {
            await manager.start()
        }
    }
}
