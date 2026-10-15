import AVFoundation

@main struct AudioLevelTests {
    static func main() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        buffer.frameLength = 1024
        let samples = buffer.floatChannelData![0]
        let meter = AudioLevel()
        for index in 0..<1024 { samples[index] = 0 }
        meter.capture(buffer)
        assert(meter.read() == 0)
        for index in 0..<1024 { samples[index] = 0.1 }
        meter.capture(buffer)
        assert(abs(meter.read() - 0.9) < 0.01)
        for index in 0..<1024 { samples[index] = 1 }
        meter.capture(buffer)
        assert(meter.read() == 1)
        meter.reset()
        assert(meter.read() == 0)
        print("PASS: RMS silence, amplitude response, clamping and reset")
    }
}
