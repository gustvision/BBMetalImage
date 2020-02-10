//
//  SeekableVideoSource.swift
//  BBMetalImage
//
//  Created by Louis Fournier on 2/10/20.
//  Copyright © 2020 Kaibo Lu. All rights reserved.
//

import AVFoundation

/// Video source reading video frame and providing Metal texture
public class SeekableVideoSource {
    /// Image consumers
    public var consumers: [BBMetalImageConsumer] {
        lock.wait()
        let c = _consumers
        lock.signal()
        return c
    }
    private var _consumers: [BBMetalImageConsumer]

    private let url: URL
    private let lock: DispatchSemaphore

    private var asset: AVAsset!
    public var player: AVPlayer!
    public var assetDuration: CMTime!
    private var videoOutput: AVPlayerItemVideoOutput!
    private var displayLink: CADisplayLink!
    private var textureCache: CVMetalTextureCache!
    public var assetOrientation: BBMetalView.TextureRotation? {
        func radiansToDegrees(_ radians: Float) -> CGFloat {
            return CGFloat(radians * 180.0 / Float.pi)
        }
        guard let firstVideoTrack = self.asset.tracks(withMediaType: .video).first else {
            return nil
        }
        let transform = firstVideoTrack.preferredTransform
        let videoAngleInDegree = radiansToDegrees(atan2f(Float(transform.b), Float(transform.a)))
        switch Int(videoAngleInDegree) {
        case 0: return .rotate0Degrees
        case 90: return .rotate90Degrees
        case 180: return .rotate180Degrees
        case -90: return .rotate270Degrees
        default: return nil
        }
    }
    
    public init?(url: URL) {
        _consumers = []
        self.url = url
        lock = DispatchSemaphore(value: 1)
        
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, BBMetalDevice.sharedDevice, nil, &textureCache) != kCVReturnSuccess ||
            textureCache == nil {
            return nil
        }
        
        self.asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey : true
            ,   AVURLAssetReferenceRestrictionsKey : 0 // AVAssetReferenceRestrictions.RestrictionForbidNone
        ])
        self.asset = AVURLAsset(url: url)
        self.assetDuration = self.asset.duration
        self.preparePlayer()
    }
    
    /// Starts reading and processing video frame
    ///
    /// - Parameter completion: a closure to call after processing; The parameter of closure is true if succeed processing all video frames, or false if fail to processing all the video frames (due to user cancel or error)
    /* removed progress and completion handler for simplicity. cuz' progress requires presentation timestamps and that isn't trivial */
    public func start(/* removed params' see comment above */) {
        lock.wait()
        let isReading = (player != nil)
        lock.signal()
        if isReading {
            print("Should not call \(#function) while player is reading")
            return
        }

        self.player.play()
//        let asset = AVAsset(url: url)
//        asset.loadValuesAsynchronously(forKeys: ["tracks"]) { [weak self] in
//            guard let self = self else { return }
//            if asset.statusOfValue(forKey: "tracks", error: nil) == .loaded,
//                asset.tracks(withMediaType: .video).first != nil {
//                DispatchQueue.global().async { [weak self] in
//                    guard let self = self else { return }
////                    self.lock.wait()
//                    self.asset = asset
//                    if self.preparePlayer() {
////                        self.lock.signal()
//                        self.player.play()
//                        // TODO: Fully replace this.
//                        // already added .play() . but there is the callback and all
//                        // self.processAsset(progress: progress, completion: completion)
//                    } else {
////                        self.reset()
////                        self.lock.signal()
//                    }
//                }
//            } else {
////                self.safeReset()
//            }
//        }
    }
    
    /// Cancels reading and processing video frame
//    public func cancel() {
//        lock.wait()
//        if let reader = assetReader,
//            reader.status == .reading {
//            reader.cancelReading()
//            reset()
//        }
//        lock.signal()
//    }
//
//    private func safeReset() {
//        lock.wait()
//        reset()
//        lock.signal()
//    }
    
//    private func reset() {
//        asset = nil
//        assetReader = nil
//        videoOutput = nil
//        audioOutput = nil
//        lastAudioBuffer = nil
//    }

    private func preparePlayer() -> Bool {
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
        self.player.automaticallyWaitsToMinimizeStalling = false
        self.videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        playerItem.add(self.videoOutput)
        self.displayLink = CADisplayLink(target: self, selector: #selector(displayLinkCallback(_:)))
        self.displayLink.add(to: RunLoop.current, forMode: .default)
        return true
    }

    @objc private func displayLinkCallback(_ sender: CADisplayLink) {
        var outputItemTime = CMTime.invalid
        let nextVSync = sender.timestamp + sender.duration
        outputItemTime = self.videoOutput.itemTime(forHostTime: nextVSync)
        guard self.videoOutput.hasNewPixelBuffer(forItemTime: outputItemTime) else { return }
        if
                let pixelBuffer = self.videoOutput.copyPixelBuffer(forItemTime: outputItemTime, itemTimeForDisplay: nil)
            ,   let texture = texture(with: pixelBuffer) {
            lock.signal()
            let sampleTime = player.currentTime() // i dont think currentTime == sampleTime but its probably close enough
            let output = BBMetalDefaultTexture(metalTexture: texture.metalTexture, sampleTime: sampleTime, cvMetalTexture: texture.cvMetalTexture)
            for consumer in consumers { consumer.newTextureAvailable(output, from: self) }
            lock.wait()
        }
    }
 
//    private func processAsset(progress: BBMetalVideoSourceProgress?, completion: BBMetalVideoSourceCompletion?) {
//        lock.wait()
//        guard let p = self.player,
////            reader.status == .unknown,
//            p.play() else {
//            reset()
//            lock.signal()
//            return
//        }
//        lock.signal()
//
//        // Read and process video buffer
//        lock.wait()
//        while let p = self.player,
////            reader.status == .reading,
//            let sampleBuffer = videoOutput.copyNextSampleBuffer(),
//            let texture = texture(with: sampleBuffer) {
//                let sampleFrameTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
//                /* There was a check of _playWithVideoRate.
//                 if it was true than some logic was triggering an usleep()
//                 to simulate real playback rate.
//                 we do not need that anymore since we will have playback rate by default.
//                 */
//                let consumers = _consumers
//
//                lock.signal()
//
//                // Transmit video texture
//                let output = BBMetalDefaultTexture(metalTexture: texture.metalTexture,
//                                                   sampleTime: sampleFrameTime,
//                                                   cvMetalTexture: texture.cvMetalTexture)
//                for consumer in consumers { consumer.newTextureAvailable(output, from: self) }
//                progress?(sampleFrameTime)
//
//                lock.wait()
//        }
//        var finish = false
//        if assetReader != nil {
//            finish = true
//            reset()
//        }
//        lock.signal()
//
//        completion?(finish)
//    }

    private func texture(with pixelBuffer: CVPixelBuffer) -> BBMetalVideoTextureItem? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvMetalTextureOut: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault
            ,   textureCache
            ,   pixelBuffer
            ,   nil
            ,   .bgra8Unorm
            ,   width
            ,   height
            ,   0
            ,   &cvMetalTextureOut)
        if result == kCVReturnSuccess,
            let cvMetalTexture = cvMetalTextureOut,
            let texture = CVMetalTextureGetTexture(cvMetalTexture) {
            return BBMetalVideoTextureItem(metalTexture: texture, cvMetalTexture: cvMetalTexture)
        }
        return nil
    }
}

extension SeekableVideoSource: BBMetalImageSource {
    @discardableResult
    public func add<T: BBMetalImageConsumer>(consumer: T) -> T {
        lock.wait()
        _consumers.append(consumer)
        lock.signal()
        consumer.add(source: self)
        // if first consumer create the CADisplayLink and shit. Can we add videooutput while playing ?
        return consumer
    }
    
    public func add(consumer: BBMetalImageConsumer, at index: Int) {
        lock.wait()
        _consumers.insert(consumer, at: index)
        lock.signal()
        consumer.add(source: self)
    }
    
    public func remove(consumer: BBMetalImageConsumer) {
        lock.wait()
        if let index = _consumers.firstIndex(where: { $0 === consumer }) {
            _consumers.remove(at: index)
            lock.signal()
            consumer.remove(source: self)
        } else {
            lock.signal()
        }
    }
    
    public func removeAllConsumers() {
        lock.wait()
        let consumers = _consumers
        _consumers.removeAll()
        lock.signal()
        for consumer in consumers {
            consumer.remove(source: self)
        }
    }
}
