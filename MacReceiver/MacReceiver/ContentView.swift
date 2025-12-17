/*
 * Meta Wearables Mac Receiver
 * Created by humanwritten
 *
 * Main view displaying video stream from Meta AI glasses
 */

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ReceiverViewModel()

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            if let frame = viewModel.currentFrame {
                // Video frame
                Image(nsImage: frame)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Waiting for connection
                VStack(spacing: 20) {
                    Image(systemName: "glasses")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)

                    Text("Meta Glasses Receiver")
                        .font(.title)
                        .foregroundColor(.white)

                    Text(viewModel.statusText)
                        .font(.headline)
                        .foregroundColor(.gray)

                    if viewModel.isSearching {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                }
            }

            // Stats overlay
            VStack {
                HStack {
                    // Connection status
                    HStack(spacing: 8) {
                        Circle()
                            .fill(viewModel.statusColor)
                            .frame(width: 12, height: 12)

                        Text(viewModel.connectionText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(10)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)

                    Spacer()

                    // Stats when streaming
                    if viewModel.isReceiving {
                        HStack(spacing: 16) {
                            StatView(label: "FPS", value: String(format: "%.1f", viewModel.frameRate))
                            StatView(label: "Bandwidth", value: viewModel.bandwidthText)
                            StatView(label: "Latency", value: viewModel.latencyText)
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    }
                }
                .padding()

                Spacer()

                // Controls
                HStack {
                    Button(action: { viewModel.toggleRecording() }) {
                        Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 24))
                            .foregroundColor(viewModel.isRecording ? .red : .white)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.isRecording ? "Stop Recording" : "Start Recording")

                    Button(action: { viewModel.saveScreenshot() }) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Save Screenshot")
                    .disabled(viewModel.currentFrame == nil)

                    Spacer()

                    // Source info
                    if let source = viewModel.connectedSource {
                        Text("Source: \(source)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.6))
            }
        }
        .onAppear {
            viewModel.startReceiving()
        }
        .onDisappear {
            viewModel.stopReceiving()
        }
    }
}

struct StatView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 14, weight: .medium).monospacedDigit())
                .foregroundColor(.white)
        }
    }
}

// MARK: - ViewModel

@MainActor
class ReceiverViewModel: ObservableObject {
    @Published var currentFrame: NSImage?
    @Published var isReceiving = false
    @Published var isRecording = false
    @Published var frameRate: Double = 0
    @Published var bytesPerSecond: Int = 0
    @Published var latencyMs: Double = 0
    @Published var connectedSource: String?

    private let relay = VideoRelayService(mode: .receiver, deviceName: Host.current().localizedName ?? "Mac Receiver")
    private var lastFrameTime: Date?

    var isSearching: Bool {
        !relay.connectionState.isConnected && relay.connectionState != .disconnected
    }

    var statusText: String {
        switch relay.connectionState {
        case .disconnected:
            return "Starting..."
        case .connecting:
            return "Searching for iOS device..."
        case .connected:
            return "Connected - Waiting for stream..."
        }
    }

    var connectionText: String {
        switch relay.connectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Searching..."
        case .connected(let count):
            return "\(count) device\(count == 1 ? "" : "s") connected"
        }
    }

    var statusColor: Color {
        switch relay.connectionState {
        case .disconnected:
            return .red
        case .connecting:
            return .orange
        case .connected:
            return isReceiving ? .green : .yellow
        }
    }

    var bandwidthText: String {
        if bytesPerSecond > 1_000_000 {
            return String(format: "%.1f MB/s", Double(bytesPerSecond) / 1_000_000)
        } else if bytesPerSecond > 1_000 {
            return String(format: "%.0f KB/s", Double(bytesPerSecond) / 1_000)
        }
        return "\(bytesPerSecond) B/s"
    }

    var latencyText: String {
        String(format: "%.0f ms", latencyMs)
    }

    init() {
        // Observe relay changes
        Task { @MainActor in
            for await frame in relay.$receivedFrame.values {
                if let frame = frame {
                    self.currentFrame = frame
                    self.isReceiving = true

                    // Calculate latency (approximate)
                    if let lastTime = self.lastFrameTime {
                        let delta = Date().timeIntervalSince(lastTime) * 1000
                        self.latencyMs = delta
                    }
                    self.lastFrameTime = Date()
                }
            }
        }

        Task { @MainActor in
            for await _ in relay.$frameRate.values {
                self.frameRate = relay.frameRate
            }
        }

        Task { @MainActor in
            for await _ in relay.$bytesPerSecond.values {
                self.bytesPerSecond = relay.bytesPerSecond
            }
        }

        Task { @MainActor in
            for await _ in relay.$connectedPeers.values {
                self.connectedSource = relay.connectedPeers.first?.displayName
            }
        }
    }

    func startReceiving() {
        relay.start()
    }

    func stopReceiving() {
        relay.stop()
    }

    func toggleRecording() {
        isRecording.toggle()
        // TODO: Implement actual recording to file
        if isRecording {
            print("[Receiver] Started recording")
        } else {
            print("[Receiver] Stopped recording")
        }
    }

    func saveScreenshot() {
        guard let image = currentFrame else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "glasses-screenshot-\(Int(Date().timeIntervalSince1970)).png"

        if panel.runModal() == .OK, let url = panel.url {
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
                print("[Receiver] Saved screenshot to \(url.path)")
            }
        }
    }
}

#Preview {
    ContentView()
}
