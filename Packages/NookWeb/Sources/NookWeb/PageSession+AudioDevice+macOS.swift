// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  PageSession+AudioDevice+macOS.swift
//  NookWeb
//
//  Core Audio's hardware object API is macOS only: a listener on the default output device
//  tells a page with audio content whether sound is coming out.
//

#if os(macOS)
import CoreAudio
import Foundation

extension PageSession {
    func setupCoreAudioPropertyListeners() {
        guard !hasAddedCoreAudioListener else { return }

        let helper = AudioListenerHelper(session: self)
        audioListenerHelper = helper

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        audioDeviceListenerProc = { (objectID, numAddresses, addresses, clientData) in
            guard let clientData = clientData else { return noErr }
            let helper = Unmanaged<AudioListenerHelper>.fromOpaque(clientData).takeUnretainedValue()

            if let session = helper.session {
                DispatchQueue.main.async {
                    session.checkNativeAudioActivity()
                }
            }

            return noErr
        }

        if let listenerProc = audioDeviceListenerProc {
            let status = AudioObjectAddPropertyListener(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                listenerProc,
                Unmanaged.passRetained(helper).toOpaque()
            )

            if status == noErr {
                hasAddedCoreAudioListener = true
            } else {
                // Registration failed — release the retained helper
                Unmanaged.passUnretained(helper).release()
            }
        }
    }

    func removeCoreAudioPropertyListeners() {
        guard hasAddedCoreAudioListener, let listenerProc = audioDeviceListenerProc,
              let helper = audioListenerHelper else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

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
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else {
            return false
        }

        var isRunning: UInt32 = 0
        dataSize = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere

        let runningStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &isRunning
        )

        return runningStatus == noErr && isRunning != 0
    }
}
#endif
