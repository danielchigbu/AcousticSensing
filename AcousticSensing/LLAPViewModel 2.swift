import Foundation
import Combine

// ViewModel that bridges SwiftUI with the Objective-C AudioController
// - Single sampling path (timer) for both gesture and breath modes
// - EMA smoothing for distance and velocity
// - Robust gesture detection (median-based threshold + hysteresis)
// - Breath detection via autocorrelation with quality metric
// - Calibration persistence and CSV logging/export
final class LLAPViewModel: ObservableObject {
    // Public UI state
    @Published var distance: Double = 0
    @Published var gesture: String = ""
    @Published var isRunning: Bool = false

    // Breath mode
    @Published var breathMode: Bool = false { didSet { handleBreathModeChange() } }
    @Published var breathRate: Double = 0.0   // breaths per minute
    @Published var breathQuality: Double = 0.0 // 0..1 (rough)

    // Gesture options
    @Published var invertGesture: Bool = false

    // Calibration (persisted)
    @Published var baseSensitivity: Double = {
        let v = UserDefaults.standard.double(forKey: "LLAP.baseSensitivity")
        return v == 0 ? 0.001 : v
    }() { didSet { UserDefaults.standard.set(baseSensitivity, forKey: "LLAP.baseSensitivity") } }

    @Published var medianMultiplier: Double = {
        let v = UserDefaults.standard.double(forKey: "LLAP.medianMultiplier")
        return v == 0 ? 1.0 : v
    }() { didSet { UserDefaults.standard.set(medianMultiplier, forKey: "LLAP.medianMultiplier") } }

    // Debug outputs for tuning
    @Published var debugVelocity: Double = 0
    @Published var debugThrHigh: Double = 0
    @Published var debugThrLow: Double = 0

    // Live graph data (last ~3s at 50 Hz)
    @Published var velocityHistory: [Double] = []
    private let historyMaxCount = 150

    // Logging
    @Published var loggingEnabled: Bool = false
    @Published var exportURL: URL?
    private var logSamples: [String] = []

    // Native controller
    private let controller = AudioController()

    // Smoothing (Exponential Moving Average) for distance
    private var smoothedDistance: Double?
    private let smoothingAlpha: Double = 0.12 // 0.1–0.2 typical

    // Velocity smoothing (EMA)
    private var velocitySmoothed: Double?
    private let velocityAlpha: Double = 0.5 // react faster to changes

    // Sampling
    private var sampleTimer: Timer?
    private let sampleInterval: TimeInterval = 0.02 // ~50 Hz

    // Gesture detection (adaptive threshold)
    private var lastDistance: Double?
    private var recentVelocities: [Double] = []
    private let velocityWindowSeconds: Double = 1.0
    private var velocityWindowSamples: Int { Int(velocityWindowSeconds / sampleInterval) }
    private var gestureState: Int = 0 // -1 closer, 0 stable, 1 away

    // Breath detection
    private let breathWindowSeconds: Double = 20.0
    private var breathSamples: [Double] = []
    private var minPeakDistanceSeconds: Double = 0.8
    private var minPeakDistanceSamples: Int { Int(minPeakDistanceSeconds / sampleInterval) }

    deinit {
        stopSampleTimer()
        _ = stop()
    }

    @discardableResult
    func start() -> Bool {
        let status = controller.startIOUnit()
        isRunning = (status == 0)
        if isRunning {
            startSampleTimer()
        }
        return isRunning
    }

    @discardableResult
    func stop() -> Bool {
        stopSampleTimer()
        let status = controller.stopIOUnit()
        isRunning = false
        return (status == 0)
    }

    private func startSampleTimer() {
        stopSampleTimer()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let raw = Double(self.controller.audiodistance)
            let filtered = self.lowPass(raw)
            DispatchQueue.main.async {
                self.distance = filtered
                if self.breathMode {
                    self.updateBreathRate(with: filtered)
                    self.gesture = "Breath mode"
                    // Maintain history in breath mode too (for graph)
                    let prev = self.lastDistance ?? filtered
                    let vSm = self.lowPassVelocity(filtered - prev)
                    self.appendHistory(vSm)
                } else {
                    self.updateGestureFromFiltered(filtered)
                }

                // Logging
                if self.loggingEnabled {
                    let ts = Date().timeIntervalSince1970
                    let line = String(format: "%.3f,%.6f,%.6f,%@,%d,%.3f", ts, self.distance, self.debugVelocity, self.gesture, self.breathMode ? 1 : 0, self.breathRate)
                    self.logSamples.append(line)
                    if self.logSamples.count > 5000 { self.logSamples.removeFirst(self.logSamples.count - 5000) }
                }
            }
        }
        RunLoop.main.add(sampleTimer!, forMode: .common)
    }

    private func stopSampleTimer() {
        sampleTimer?.invalidate()
        sampleTimer = nil
    }

    // MARK: - Smoothing
    private func lowPass(_ x: Double) -> Double {
        if let yPrev = smoothedDistance {
            let y = (1.0 - smoothingAlpha) * yPrev + smoothingAlpha * x
            smoothedDistance = y
            return y
        } else {
            smoothedDistance = x
            return x
        }
    }

    private func lowPassVelocity(_ v: Double) -> Double {
        if let vPrev = velocitySmoothed {
            let y = (1.0 - velocityAlpha) * vPrev + velocityAlpha * v
            velocitySmoothed = y
            return y
        } else {
            velocitySmoothed = v
            return v
        }
    }

    private func appendHistory(_ v: Double) {
        velocityHistory.append(v)
        if velocityHistory.count > historyMaxCount {
            velocityHistory.removeFirst(velocityHistory.count - historyMaxCount)
        }
    }

    // MARK: - Gesture
    private func updateGestureFromFiltered(_ filtered: Double) {
        let prev = lastDistance ?? filtered
        let rawVelocity = filtered - prev
        let vSm = lowPassVelocity(rawVelocity)
        lastDistance = filtered

        appendHistory(vSm)

        // keep recent absolute velocities for robust thresholding
        recentVelocities.append(abs(vSm))
        if recentVelocities.count > velocityWindowSamples {
            recentVelocities.removeFirst(recentVelocities.count - velocityWindowSamples)
        }

        let medianAbs = median(of: recentVelocities)
        let thrBase = max(baseSensitivity, medianMultiplier * medianAbs)
        let high = thrBase * 1.2
        let low  = thrBase * 0.9

        // Optionally invert sign for devices where direction is reversed
        let sV = invertGesture ? -vSm : vSm

        // Publish debug values for tuning (optional UI)
        debugVelocity = sV
        debugThrHigh = high
        debugThrLow  = low

        switch gestureState {
        case -1: // currently closer
            if sV < -low {
                gesture = "Moving Closer"
            } else if sV > -low/2 { // small hysteresis back to stable
                gestureState = 0
                gesture = "Stable"
            }
        case 1: // currently away
            if sV > low {
                gesture = "Moving Away"
            } else if sV < low/2 { // small hysteresis back to stable
                gestureState = 0
                gesture = "Stable"
            }
        default: // stable
            if sV > high {
                gestureState = 1
                gesture = "Moving Away"
            } else if sV < -high {
                gestureState = -1
                gesture = "Moving Closer"
            } else {
                gesture = "Stable"
            }
        }
    }

    private func median(of arr: [Double]) -> Double {
        guard !arr.isEmpty else { return 0 }
        let sorted = arr.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return 0.5 * (sorted[mid - 1] + sorted[mid])
        } else {
            return sorted[mid]
        }
    }

    // MARK: - Breath
    private func handleBreathModeChange() {
        // reset state when toggling modes
        breathSamples.removeAll()
        recentVelocities.removeAll()
        smoothedDistance = nil
        velocitySmoothed = nil
        lastDistance = nil
        breathQuality = 0
    }

    private func updateBreathRate(with value: Double) {
        // Sliding window
        breathSamples.append(value)
        let maxCount = Int(breathWindowSeconds / sampleInterval)
        if breathSamples.count > maxCount {
            breathSamples.removeFirst(breathSamples.count - maxCount)
        }

        // Need enough data first (~2s)
        guard breathSamples.count >= 100 else {
            breathRate = 0.0
            breathQuality = 0.0
            return
        }

        // Detrend using mean baseline
        let mean = breathSamples.reduce(0, +) / Double(breathSamples.count)
        let detrended = breathSamples.map { $0 - mean }

        // Autocorrelation within plausible breathing range (8–35 bpm)
        let minBPM = 8.0, maxBPM = 35.0
        let minLag = max(1, Int((60.0 / maxBPM) / sampleInterval))   // ~1.7s -> ~85 samples
        let maxLag = min(detrended.count - 1, Int((60.0 / minBPM) / sampleInterval)) // ~7.5s -> ~375 samples
        if maxLag <= minLag { breathRate = 0; breathQuality = 0; return }

        // energy for normalization
        let energy = max(1e-9, detrended.reduce(0) { $0 + $1*$1 })
        var bestLag = minLag
        var bestCorr = -Double.infinity
        var l = minLag
        while l <= maxLag {
            var corr = 0.0
            var i = 0
            while i + l < detrended.count {
                corr += detrended[i] * detrended[i + l]
                i += 1
            }
            let normCorr = corr / energy
            if normCorr > bestCorr {
                bestCorr = normCorr
                bestLag = l
            }
            l += 1
        }

        breathQuality = max(0.0, min(1.0, bestCorr))
        if bestCorr > 0.05 { // require minimum quality
            breathRate = 60.0 / (Double(bestLag) * sampleInterval)
        } else {
            breathRate = 0.0
        }
    }

    // MARK: - Export
    func exportLog() {
        let header = "timestamp,distance,velocity,gesture,breathMode,breathRate"
        let csv = ([header] + logSamples).joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("acoustic_log_\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }
}
