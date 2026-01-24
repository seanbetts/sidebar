import SwiftUI
import AVFoundation
import Combine

public struct AudioPlayerView: View {
    @StateObject private var viewModel: AudioPlayerViewModel

    public init(url: URL) {
        _viewModel = StateObject(wrappedValue: AudioPlayerViewModel(url: url))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button(
                    action: { viewModel.togglePlay() },
                    label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(DesignTokens.Typography.titleMd)
                            .frame(width: 36, height: 36)
                    }
                )
                .buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { viewModel.progress },
                            set: { viewModel.seek(to: $0) }
                        )
                    )
                    HStack {
                        Text(viewModel.elapsedText)
                        Spacer()
                        Text(viewModel.durationText)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

@MainActor
final class AudioPlayerViewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0

    private let url: URL
    private var player: AVAudioPlayer?
    private var timer: Timer?

    init(url: URL) {
        self.url = url
        preparePlayer()
    }

    var durationText: String {
        formatTime(player?.duration ?? 0)
    }

    var elapsedText: String {
        formatTime((player?.currentTime ?? 0))
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to value: Double) {
        guard let player = player, player.duration > 0 else { return }
        player.currentTime = value * player.duration
        updateProgress()
    }

    func stop() {
        player?.stop()
        isPlaying = false
        invalidateTimer()
    }

    private func preparePlayer() {
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.prepareToPlay()
            player = audioPlayer
            updateProgress()
        } catch {
            player = nil
        }
    }

    private func play() {
        guard let player = player else { return }
        player.play()
        isPlaying = true
        startTimer()
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        invalidateTimer()
    }

    private func startTimer() {
        invalidateTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateProgress()
            }
        }
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateProgress() {
        guard let player = player, player.duration > 0 else {
            progress = 0
            return
        }
        progress = player.currentTime / player.duration
        if player.currentTime >= player.duration {
            isPlaying = false
            invalidateTimer()
        }
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let totalSeconds = Int(value.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
