import Foundation

#if os(iOS)
import AVFoundation
#endif

enum MediaPlaybackAudioSession {
    static func activateForPlayback() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            return
        }
        #endif
    }
}
