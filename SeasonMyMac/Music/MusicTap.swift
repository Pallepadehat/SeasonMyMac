import AudioToolbox
import CoreAudio
import Foundation
import OSLog
import os

/// Listens to one app's audio output through a Core Audio process tap
/// (macOS 14.2 and later) and boils it down to loudness and beats.
///
/// No sound is recorded or stored: each buffer is reduced to a couple of
/// numbers on the audio thread and then dropped. macOS asks the user once
/// before the app may listen to other apps' audio.
nonisolated final class MusicTap: @unchecked Sendable {
    struct Reading {
        /// 0...1, smoothed.
        var level: Float = 0
        var beatCount = 0
        /// Seconds since boot of the last beat.
        var lastBeat: Double = 0
        /// Seconds since boot of the last buffer that wasn't silent.
        var lastSound: Double = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: Reading())
    private let queue = DispatchQueue(label: "SeasonMyMac.MusicTap", qos: .userInteractive)

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    // Analysis state, only touched on the audio queue.
    private var lowPass: Float = 0
    private var bassAverage: Float = 0
    private var loudnessPeak: Float = 0.02
    private var smoothedLevel: Float = 0

    let processID: pid_t

    /// Starts listening to `processID`. Fails if the system refuses the tap.
    init?(processID: pid_t) {
        self.processID = processID
        guard #available(macOS 14.2, *), start() else {
            stop()
            return nil
        }
    }

    deinit {
        stop()
    }

    var reading: Reading {
        state.withLock { $0 }
    }

    // MARK: Setup

    @available(macOS 14.2, *)
    private func start() -> Bool {
        guard let processObject = Self.processObject(for: processID) else {
            Logger.music.info("No audio process for pid \(self.processID)")
            return false
        }

        let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        description.name = "SeasonMyMac lights"

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            Logger.music.error("Couldn't tap the music app's audio: \(status)")
            return false
        }

        guard let outputUID = Self.defaultOutputDeviceUID() else { return false }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SeasonMyMac Music",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else {
            Logger.music.error("Couldn't create the listening device: \(status)")
            return false
        }

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.analyze(input)
        }
        guard status == noErr else { return false }
        status = AudioDeviceStart(aggregateID, procID)
        return status == noErr
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    // MARK: Analysis

    /// Loudness from the RMS of the buffer, beats from sudden jumps in bass energy.
    private func analyze(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        var sumSquares: Float = 0
        var bassSquares: Float = 0
        var count = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            for index in 0..<sampleCount {
                let sample = samples[index]
                sumSquares += sample * sample
                // A one-pole low-pass at roughly 150 Hz keeps the kick drum and bass.
                lowPass += (sample - lowPass) * 0.02
                bassSquares += lowPass * lowPass
            }
            count += sampleCount
        }
        guard count > 0 else { return }

        let rms = (sumSquares / Float(count)).squareRoot()
        let bass = bassSquares / Float(count)
        let now = ProcessInfo.processInfo.systemUptime

        // Normalise loudness against a slowly falling peak, so quiet and loud tracks both fill the range.
        loudnessPeak = max(rms, loudnessPeak * 0.9995, 0.02)
        let level = min(1, rms / loudnessPeak)
        smoothedLevel += (level - smoothedLevel) * (level > smoothedLevel ? 0.5 : 0.12)

        let isBeat = bass > bassAverage * 1.5 && bass > 0.0004
        bassAverage += (bass - bassAverage) * 0.05

        state.withLock { reading in
            reading.level = smoothedLevel
            if rms > 0.002 { reading.lastSound = now }
            if isBeat, now - reading.lastBeat > 0.26 {
                reading.lastBeat = now
                reading.beatCount += 1
            }
        }
    }

    // MARK: Core Audio lookups

    private static func processObject(for pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}
