# Acoustic Sensing on iOS (LLAP)

Real-time ultrasonic ranging and gesture detection on an iPhone using only the built-in speaker and microphone.  
Developed for **Practical Acoustic Sensing (CSCI 4900/6900)**.

## Overview

This project implements an end-to-end acoustic sensing pipeline entirely in Xcode.  
The app emits an ultrasonic signal from the iPhone’s speaker, records the echoes with the microphone, and uses the LLAP (Low-Latency Acoustic Probing) engine to estimate the distance to nearby objects in real time.

A SwiftUI interface displays:

- The **current distance** estimate, and  
- A **gesture label** indicating whether a hand above the phone is *moving closer* or *moving away*.

All sensing and processing run **on-device** — no MATLAB or external tools are required.

## Technical Highlights

- iOS app written in **Swift + SwiftUI**
- Low-level audio implemented in **Objective-C / C++** using **CoreAudio**
- Real-time polling of ultrasonic range estimates (~50 Hz)
- Simple gesture classification based on distance changes
- Bridging header used to expose the LLAP engine to Swift

## System Architecture

**Core components:**

- `AudioController.(h/mm)`  
  - Configures the audio session and RemoteIO unit  
  - Plays the ultrasonic probe signal  
  - Feeds microphone buffers into the ranging engine  
  - Exposes a public `audiodistance` value

- `RangeFinder.(h/cpp)`  
  - Implements the LLAP-style ranging algorithm  
  - Converts reflected chirp delays into a distance estimate

- `CAStreamBasicDescription`, `CADebugMacros`, `CADebugPrintf`, `CAMath`  
  - CoreAudio utility code used by the LLAP engine

- `AcousticSensing-Bridging-Header.h`  
  - Exposes `AudioController` to Swift

- `LLAPViewModel.swift`  
  - Starts/stops `AudioController`  
  - Polls `audiodistance` on a timer (~0.02 s)  
  - Tracks last distance and classifies gestures:
    - `Moving Closer`
    - `Moving Away`
  - Publishes data to SwiftUI using `@Published` and `ObservableObject`

- `ContentView.swift`  
  - SwiftUI view showing:
    - Title  
    - Live distance value  
    - Gesture label  
    - Instructions to move the hand above the phone

## Build & Run

### Requirements

- macOS with **Xcode** (15+ recommended)
- An **iPhone** (physical device – simulator will not work for ultrasound)
- iOS 16+ (or your deployment target)
- Apple ID for signing (free or paid developer)

### Steps

1. **Clone this repository**

   ```bash
   git clone https://github.com/<your-username>/acoustic-sensing-ios.git
   cd acoustic-sensing-ios
