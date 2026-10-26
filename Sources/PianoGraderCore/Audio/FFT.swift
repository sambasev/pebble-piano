import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Magnitude spectrum of a real signal: a power-of-two FFT, using vDSP on Apple platforms
/// and a plain radix-2 FFT elsewhere (so the same code runs in Linux tests).
public final class MagnitudeFFT {
    public let size: Int
    private let log2n: Int
    private var real: [Float]
    private var imag: [Float]
    #if canImport(Accelerate)
    private let setup: FFTSetup
    #else
    private let cosTable: [Float]
    private let sinTable: [Float]
    private let bitReverse: [Int]
    #endif

    /// - Parameter size: a power of two (the FFT length).
    public init(size: Int) {
        precondition(size >= 8 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        self.log2n = Int(log2(Double(size)).rounded())
        real = [Float](repeating: 0, count: size)
        imag = [Float](repeating: 0, count: size)
        #if canImport(Accelerate)
        setup = vDSP_create_fftsetup(vDSP_Length(log2n), FFTRadix(kFFTRadix2))!
        #else
        cosTable = (0..<size / 2).map { Float(cos(-2 * Double.pi * Double($0) / Double(size))) }
        sinTable = (0..<size / 2).map { Float(sin(-2 * Double.pi * Double($0) / Double(size))) }
        var reverse = [Int](repeating: 0, count: size)
        for i in 0..<size {
            var r = 0, x = i
            for _ in 0..<Int(log2(Double(size)).rounded()) { r = (r << 1) | (x & 1); x >>= 1 }
            reverse[i] = r
        }
        bitReverse = reverse
        #endif
    }

    deinit {
        #if canImport(Accelerate)
        vDSP_destroy_fftsetup(setup)
        #endif
    }

    /// Magnitudes of bins 0..<count of `input` (zero-padded or truncated to `size`).
    /// `count` is at most size / 2.
    public func magnitudes(of input: [Float], count: Int, into output: inout [Float]) {
        let n = min(input.count, size)
        for i in 0..<size {
            real[i] = i < n ? input[i] : 0
            imag[i] = 0
        }
        transform()
        let bins = min(count, size / 2)
        if output.count != bins { output = [Float](repeating: 0, count: bins) }
        for k in 0..<bins {
            output[k] = (real[k] * real[k] + imag[k] * imag[k]).squareRoot()
        }
    }

    private func transform() {
        #if canImport(Accelerate)
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, vDSP_Length(log2n), FFTDirection(kFFTDirection_Forward))
            }
        }
        #else
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                for i in 0..<size {
                    let j = bitReverse[i]
                    if j > i {
                        re.swapAt(i, j)
                        im.swapAt(i, j)
                    }
                }
                var length = 2
                while length <= size {
                    let half = length / 2
                    let step = size / length
                    var start = 0
                    while start < size {
                        var t = 0
                        for k in 0..<half {
                            let wr = cosTable[t], wi = sinTable[t]
                            let a = start + k, b = a + half
                            let xr = re[b] * wr - im[b] * wi
                            let xi = re[b] * wi + im[b] * wr
                            re[b] = re[a] - xr
                            im[b] = im[a] - xi
                            re[a] += xr
                            im[a] += xi
                            t += step
                        }
                        start += length
                    }
                    length <<= 1
                }
            }
        }
        #endif
    }
}
