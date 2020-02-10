//
//  PokableVideoSource.swift
//  BBMetalImage
//
//  Created by Louis Fournier on 2/10/20.
//  Copyright © 2020 Kaibo Lu. All rights reserved.
//

import AVFoundation

/*
 *  When using BBMetalVideoSource & BBMetalVideoWriter
 *  The frame whould be pulled by the videoWriter and not pushed
 *  by the videoSource (which is currently the case).
 *  Because the videoWriter can't keep up with the speed at which the
 *  videoSource sends him frames.
 *
 *  Doing a proper pull-based flow would require rethinking the entire BBMetalImage chain.
 *
 *  As a quick hack,
 *  This PokableVideoSource is a modification of BBMetalVideoSource
 *  which sends a frame only when it is poked.
 *  It will be poked whenever the videoWriter gets available for writing again.
 *  Didn't inherit from BBMetalVideoSource, but copy pasted it
 */

final class PokableVideoSource: BBMetalVideoSource {

    private var progress: BBMetalVideoSourceProgress?
    private var completion: BBMetalVideoSourceCompletion?

    override func start(progress: BBMetalVideoSourceProgress? = nil, completion: BBMetalVideoSourceCompletion? = nil) {
        self.progress = progress
        self.completion = completion
        lock.wait()
        let isReading = (assetReader != nil)
        lock.signal()
        if isReading {
            print("Should not call \(#function) while asset reader is reading")
            return
        }
        let asset = AVAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) { [weak self] in
            guard let self = self else { return }
            if asset.statusOfValue(forKey: "tracks", error: nil) == .loaded,
                asset.tracks(withMediaType: .video).first != nil {
                DispatchQueue.global().async { [weak self] in
                    guard let self = self else { return }
                    self.lock.wait()
                    self.asset = asset
                    if
                            self.prepareAssetReader()
                        ,   let reader = self.assetReader
                        ,   reader.status == .unknown
                        ,   reader.startReading() {
                        self.lock.signal()
                        /* previously call to processAsset() but useless now */
                    } else {
                        self.reset()
                        self.lock.signal()
                    }
                }
            } else {
                self.safeReset()
            }
        }
    }

    public func pullFrame() {
        lock.wait()
        if (self.assetReader == nil
            || (self.assetReader != nil && self.assetReader!.status == .unknown)) {
            /* esacping the case where writer is ready for more but reader hasnt started yet */
            lock.signal()
            print("[A] PULL! \(self.assetReader != nil) \(self.assetReader?.status == .unknown) \(self.assetReader?.status == .reading)")
            return
        }
        guard
                let reader = self.assetReader
            ,   reader.status == .reading
            ,   let sampleBuffer = videoOutput.copyNextSampleBuffer()
            ,   let texture = texture(with: sampleBuffer) else {
                //      // Read and process the rest audio buffers
                //      if let consumer = _audioConsumer,
                //          let audioBuffer = lastAudioBuffer {
                //          lock.signal()
                //          consumer.newAudioSampleBufferAvailable(audioBuffer)
                //          lock.wait()
                //      }
                //      while let consumer = _audioConsumer,
                //          let reader = assetReader,
                //          reader.status == .reading,
                //          audioOutput != nil,
                //          let audioBuffer = audioOutput.copyNextSampleBuffer() {
                //              lock.signal()
                //              consumer.newAudioSampleBufferAvailable(audioBuffer)
                //              lock.wait()
                //      }
            var finish = false
            if assetReader != nil {
                finish = true
                reset()
            }
            lock.signal()
            self.completion?(finish)
            print("[B] PULL! \(self.assetReader != nil) \(self.assetReader?.status == .unknown) \(self.assetReader?.status == .reading)")
            return
        }

        let sampleFrameTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
        let consumers = _consumers
                
        // Read and process audio buffer
        // Let video buffer go faster than audio buffer
        // Make sure audio and video buffer have similar output presentation timestamp
        var currentAudioBuffer: CMSampleBuffer?
        let currentAudioConsumer = _audioConsumer
        if currentAudioConsumer != nil {
            if
                    let last = lastAudioBuffer
                ,   CMTimeCompare(CMSampleBufferGetOutputPresentationTimeStamp(last)
                ,   sampleFrameTime) <= 0 {
                    // Process audio buffer
                    currentAudioBuffer = last
                    lastAudioBuffer = nil
            } else if
                    lastAudioBuffer == nil
                ,   audioOutput != nil
                ,   let audioBuffer = audioOutput.copyNextSampleBuffer() {
                    if
                            CMTimeCompare(CMSampleBufferGetOutputPresentationTimeStamp(audioBuffer)
                        ,   sampleFrameTime) <= 0 {
                            // Process audio buffer
                            currentAudioBuffer = audioBuffer
                    } else {
                            // Audio buffer goes faster than video
                            // Process audio buffer later
                            lastAudioBuffer = audioBuffer
                    }
            }
        }
        lock.signal()
                
        // Transmit video texture
        let output = BBMetalDefaultTexture(
                metalTexture: texture.metalTexture
            ,   sampleTime: sampleFrameTime
            ,   cvMetalTexture: texture.cvMetalTexture)
        for consumer in consumers { consumer.newTextureAvailable(output, from: self) }
        progress?(sampleFrameTime)
                
        // Transmit audio buffer
        if let audioBuffer = currentAudioBuffer { currentAudioConsumer?.newAudioSampleBufferAvailable(audioBuffer) }
        print("[C] PULL! \(self.assetReader != nil) \(self.assetReader?.status == .unknown) \(self.assetReader?.status == .reading)")
    }
}
