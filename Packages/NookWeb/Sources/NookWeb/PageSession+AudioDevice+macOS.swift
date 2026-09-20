// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  PageSession+AudioDevice+macOS.swift
//  NookWeb
//
//  Core Audio's hardware object API is macOS only: listeners on the default output device
//  tell a page with audio content whether sound is coming out.
//

#if os(macOS)
import CoreAudio
import Foundation

extension PageSession {
    private var defaultOutputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private var deviceRunningAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func currentDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultOutputDeviceAddress
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    // ponytail: one listener pair per session on a system-wide property. Changes are rare so
    // the duplication is cheap; fold into a single app-wide observer if session counts grow.
    func setupCoreAudioPropertyListeners() {
        guard !hasAddedCoreAudioListener else { return }

        let helper = AudioListenerHelper(session: self)
        audioListenerHelper = helper

        audioDeviceListenerProc = { (_, _, _, clientData) in
            guard let clientData else { return noErr }
            let helper = Unmanaged<AudioListenerHelper>.fromOpaque(clientData).takeUnretainedValue()
            guard let session = helper.session else { return noErr }
            DispatchQueue.main.async {
                // The default device may have just changed; follow it before reading.
                session.retargetRunningListener()
                session.checkNativeAudioActivity()
            }
            return noErr
        }

        guard let listenerProc = audioDeviceListenerProc else { return }
        var address = defaultOutputDeviceAddress
        let status = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerProc,
            Unmanaged.passRetained(helper).toOpaque()
        )

        guard status == noErr else {
            Unmanaged.passUnretained(helper).release()
            audioDeviceListenerProc = nil
            audioListenerHelper = nil
            return
        }
        hasAddedCoreAudioListener = true
        retargetRunningListener()
        checkNativeAudioActivity()
    }

    /// Points the "is running somewhere" listener at whichever device is the default output now.
    /// This is what replaces the old 1 Hz poll: Core Audio reports the transition instead.
    func retargetRunningListener() {
        guard let listenerProc = audioDeviceListenerProc, let helper = audioListenerHelper else { return }
        let next = currentDefaultOutputDevice()
        guard next != audioRunningListenerDevice else { return }

        if let previous = audioRunningListenerDevice {
            var address = deviceRunningAddress
            let removed = AudioObjectRemovePropertyListener(
                AudioDeviceID(previous), &address, listenerProc,
                Unmanaged.passUnretained(helper).toOpaque())
            if removed == noErr { Unmanaged.passUnretained(helper).release() }
            audioRunningListenerDevice = nil
        }

        guard let next else { return }
        var address = deviceRunningAddress
        let added = AudioObjectAddPropertyListener(
            next, &address, listenerProc, Unmanaged.passRetained(helper).toOpaque())
        if added == noErr {
            audioRunningListenerDevice = UInt32(next)
        } else {
            Unmanaged.passUnretained(helper).release()
        }
    }

    func removeCoreAudioPropertyListeners() {
        guard hasAddedCoreAudioListener, let listenerProc = audioDeviceListenerProc,
              let helper = audioListenerHelper else { return }

        if let device = audioRunningListenerDevice {
            var address = deviceRunningAddress
            let removed = AudioObjectRemovePropertyListener(
                AudioDeviceID(device), &address, listenerProc,
                Unmanaged.passUnretained(helper).toOpaque())
            if removed == noErr { Unmanaged.passUnretained(helper).release() }
            audioRunningListenerDevice = nil
        }

        var address = defaultOutputDeviceAddress
        let status = AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerProc,
            Unmanaged.passUnretained(helper).toOpaque()
        )

        if status == noErr {
            // Balance the passRetained from setup
            Unmanaged.passUnretained(helper).release()
            hasAddedCoreAudioListener = false
            audioDeviceListenerProc = nil
            audioListenerHelper = nil
        }
    }

    func isDefaultAudioDeviceActive() -> Bool {
        guard let deviceID = currentDefaultOutputDevice() else { return false }
        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        var address = deviceRunningAddress
        let status = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &dataSize, &isRunning)
        return status == noErr && isRunning != 0
    }
}
#endif
