//
//  ContentView.swift
//  AcousticSensing
//
//  Created by Daniel Chigbu on 11/27/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject var vm = LLAPViewModel()
    @State private var baseSensitivity: Double = 0.001
    @State private var medianMultiplier: Double = 1.0

    var body: some View {
        VStack(spacing: 16) {
            Text("Acoustic Sensing")
                .font(.largeTitle)
                .bold()

            // Mode switch
            Toggle("Breath mode", isOn: $vm.breathMode)
                .padding(.horizontal)

            // Always show raw distance
            Text("Distance: \(String(format: "%.3f", vm.distance))")
                .font(.title3)

            if vm.breathMode {
                // Breath mode UI
                Text("Breathing Rate: \(String(format: "%.1f", vm.breathRate)) breaths/min")
                    .font(.title2)
                    .bold()
                    .padding(.top, 8)

                Text("Place the phone 10–20 cm from your chest or face and breathe normally.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                // Gesture mode UI
                Text("Gesture: \(vm.gesture)")
                    .font(.title2)
                    .bold()

                // Calibration panel
                GroupBox("Gesture Calibration") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Invert Direction", isOn: $vm.invertGesture)
                        HStack {
                            Text("Base Sensitivity")
                            Slider(value: $baseSensitivity, in: 0.0005...0.05, step: 0.0005)
                            Text(String(format: "%.4f", baseSensitivity))
                        }
                        HStack {
                            Text("Median Multiplier")
                            Slider(value: $medianMultiplier, in: 0.5...2.5, step: 0.1)
                            Text(String(format: "%.1f", medianMultiplier))
                        }
                        // Debug readouts
                        Text(String(format: "Vel: %.4f  High: %.4f  Low: %.4f", vm.debugVelocity, vm.debugThrHigh, vm.debugThrLow))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .onChange(of: baseSensitivity) { newVal in
                    NotificationCenter.default.post(name: Notification.Name("LLAPGestureBaseSensitivity"), object: NSNumber(value: newVal))
                }
                .onChange(of: medianMultiplier) { newVal in
                    NotificationCenter.default.post(name: Notification.Name("LLAPGestureMedianMultiplier"), object: NSNumber(value: newVal))
                }

                Text("Move your hand above the phone to see gesture changes.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack(spacing: 16) {
                Button(action: { _ = vm.start() }) {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isRunning)

                Button(action: { _ = vm.stop() }) {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!vm.isRunning)
            }
            .padding(.top, 8)

            Text(vm.isRunning ? "Running" : "Stopped")
                .font(.footnote)
                .foregroundStyle(vm.isRunning ? .green : .secondary)
                .padding(.top, 4)
        }
        .padding()
        .onAppear {
            _ = vm.start()
            // Seed UI sliders via notifications so VM picks them up immediately
            NotificationCenter.default.post(name: Notification.Name("LLAPGestureBaseSensitivity"), object: NSNumber(value: 0.001))
            NotificationCenter.default.post(name: Notification.Name("LLAPGestureMedianMultiplier"), object: NSNumber(value: 1.0))
        }
    }
}

#Preview {
    ContentView()
}
