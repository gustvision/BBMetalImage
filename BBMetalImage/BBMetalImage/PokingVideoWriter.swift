//
//  PokingVideoWriter.swift
//  BBMetalImage
//
//  Created by Louis Fournier on 2/10/20.
//  Copyright © 2020 Kaibo Lu. All rights reserved.
//

import AVFoundation

final public class PokingVideoWriter: BBMetalVideoWriter {

    private var videoInputQueue: DispatchQueue!
    public var pokeBlock: (() -> Void)?

    override init(
            url: URL
        ,   frameSize: BBMetalIntSize
        ,   fileType: AVFileType = .mp4
        ,   outputSettings: [String : Any] = [AVVideoCodecKey : AVVideoCodecType.h264]
    ) {
        super.init(url: url, frameSize: frameSize, fileType: fileType, outputSettings: outputSettings)
        expectsMediaDataInRealTime = false
    }

    private func poke() {
        while videoInput.isReadyForMoreMediaData {
            pokeBlock?()
        }
    }

    override public func start(progress: BBMetalVideoWriterProgress? = nil) {
        super.start(progress: progress)
        videoInputQueue = DispatchQueue(label: "videoInput")
        videoInput.requestMediaDataWhenReady(on: videoInputQueue, using: self.poke)
    }
}
