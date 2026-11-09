import AppKit
import Observation
import SeasonKit

/// Lets the holiday lights dance to whatever's playing in Apple Music or Spotify.
///
/// Both apps announce play, pause and track changes with distributed
/// notifications, which tell us *what* is playing. To follow the beat itself,
/// the app listens to the player's audio through a Core Audio tap. If that
/// isn't available (macOS before 14.2, or access declined), the lights still
/// pulse along at a steady tempo while music plays.
@Observable
final class MusicSync: NSObject {
    enum Player: String, CaseIterable {
        case music = "Apple Music"
        case spotify = "Spotify"

        var bundleIdentifier: String {
            switch self {
            case .music: "com.apple.Music"
            case .spotify: "com.spotify.client"
            }
        }

        var notificationName: Notification.Name {
            switch self {
            case .music: Notification.Name("com.apple.Music.playerInfo")
            case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
            }
        }
    }

    struct NowPlaying: Equatable {
        var player: Player
        var title: String
        var artist: String
    }

    /// The track playing right now, if either app says so.
    private(set) var nowPlaying: NowPlaying?
    /// Whether the app is following the actual beat (rather than a steady pulse).
    private(set) var isFollowingBeat = false

    /// Set from the lights setting. Nothing is listened to while it's off.
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }

    @ObservationIgnored private var tap: MusicTap?
    @ObservationIgnored private var tapPlayer: Player?
    @ObservationIgnored private var tapStarted: Double = 0
    @ObservationIgnored private var housekeeping: Timer?
    @ObservationIgnored private var playingSince: Double = 0

    // MARK: Pulse

    /// What the lights should do this frame, or `nil` to use their normal animation.
    func pulse() -> MusicPulse? {
        guard isEnabled else { return nil }
        let now = ProcessInfo.processInfo.systemUptime

        if let tap {
            let reading = tap.reading
            if now - reading.lastSound < 1.5 {
                let beat = exp(-Float(now - reading.lastBeat) * 5)
                return MusicPulse(level: reading.level, beat: beat, beatCount: reading.beatCount)
            }
            // Recently started and nothing heard yet: fall through to the steady pulse.
            guard now - tapStarted < 4, nowPlaying != nil else { return nil }
        }

        guard nowPlaying != nil else { return nil }
        // A steady 120 beats a minute while we can't hear the music itself.
        let beats = (now - playingSince) * 2
        let phase = Float(beats - beats.rounded(.down))
        return MusicPulse(level: 0.55 + 0.25 * sin(Float(beats) * .pi / 4), beat: exp(-phase * 5), beatCount: Int(beats))
    }

    // MARK: Lifecycle

    private func start() {
        let center = DistributedNotificationCenter.default()
        for player in Player.allCases {
            center.addObserver(self, selector: #selector(playerInfoChanged(_:)), name: player.notificationName, object: nil)
        }
        // A player that's already open might be playing; listen briefly to find out.
        if let player = Player.allCases.first(where: { isRunning($0) }) {
            startTap(for: player)
        }
        housekeeping = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tidyUp() }
        }
    }

    private func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        housekeeping?.invalidate()
        housekeeping = nil
        stopTap()
        nowPlaying = nil
    }

    @objc private func playerInfoChanged(_ notification: Notification) {
        guard let player = Player.allCases.first(where: { $0.notificationName == notification.name }) else { return }
        let info = notification.userInfo ?? [:]
        let state = info["Player State"] as? String

        if state == "Playing" {
            if nowPlaying == nil { playingSince = ProcessInfo.processInfo.systemUptime }
            nowPlaying = NowPlaying(player: player, title: info["Name"] as? String ?? "", artist: info["Artist"] as? String ?? "")
            if tapPlayer != player || tap == nil {
                startTap(for: player)
            }
        } else if nowPlaying?.player == player {
            nowPlaying = nil
        }
    }

    /// Stops listening once the music has stopped for a while, or the player quit.
    private func tidyUp() {
        guard let tap, let tapPlayer else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let silentFor = now - max(tap.reading.lastSound, tapStarted)
        if !isRunning(tapPlayer) || (nowPlaying == nil && silentFor > 20) {
            stopTap()
        }
    }

    private func startTap(for player: Player) {
        stopTap()
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).first?.processIdentifier else { return }
        tap = MusicTap(processID: process)
        tapPlayer = tap == nil ? nil : player
        tapStarted = ProcessInfo.processInfo.systemUptime
        isFollowingBeat = tap != nil
    }

    private func stopTap() {
        tap?.stop()
        tap = nil
        tapPlayer = nil
        isFollowingBeat = false
    }

    private func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }
}
