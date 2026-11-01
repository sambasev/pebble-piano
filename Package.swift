// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PianoGrader",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "PianoGraderCore", targets: ["PianoGraderCore"]),
        .library(name: "PianoGraderIO", targets: ["PianoGraderIO"]),
        .library(name: "PianoPadState", targets: ["PianoPadState"]),
        .library(name: "PianoLessons", targets: ["PianoLessons"]),
        .library(name: "PianoAI", targets: ["PianoAI"]),
        .executable(name: "grade", targets: ["grade"]),
        .executable(name: "PianoPad", targets: ["PianoPad"]),
        .library(name: "EarTrainingUI", targets: ["EarTrainingUI"]),
        .library(name: "EarTrainingIntegration", targets: ["EarTrainingIntegration"]),
        .executable(name: "EarTrainer", targets: ["EarTrainer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
        // Lock-free atomics for handing data off realtime audio and MIDI threads.
        .package(url: "https://github.com/apple/swift-atomics", from: "1.2.0"),
    ],
    targets: [
        .testTarget(name: "PianoPadTests", dependencies: ["PianoPad"]),
        // Pure grading logic: no UI, no CoreMIDI, no audio. Shared by everything.
        .target(
            name: "PianoGraderCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "Atomics", package: "swift-atomics"),
            ],
            // Always optimised: the microphone detector must keep up with live audio, and an
            // unoptimised (Debug, as Xcode's Run builds) detector falls behind.
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        // Apple-platform input and output: MIDI input over CoreMIDI and piano sound.
        .target(
            name: "PianoGraderIO",
            dependencies: ["PianoGraderCore"]
        ),
        // The app's saved state: learners and their settings. Foundation only, so it is
        // unit-tested without the app.
        .target(name: "PianoPadState"),
        // Lessons: the unit/page/block format, the page state machine and stars. No UI or
        // audio, so the whole lesson journey is unit-tested.
        .target(
            name: "PianoLessons",
            dependencies: ["PianoGraderCore"]
        ),
        // Meta Model API (Muse Spark, SAM 3.1, Muse Voice Transcribe) and OpenAI-compatible
        // open-weight hosts (Fireworks, Modal). Foundation only; unit-tested with canned responses.
        .target(
            name: "PianoAI",
            dependencies: ["PianoGraderCore"],
            // Always optimised: measuring noteheads walks every pixel of each system image.
            swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]
        ),
        // Command-line tool: grade a recorded take, record one live, or check fixtures.
        .executableTarget(
            name: "grade",
            dependencies: [
                "PianoGraderCore",
                "PianoGraderIO",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // Mac app for quick testing: on-screen keyboard, musical typing, MIDI input, grading.
        .executableTarget(
            name: "PianoPad",
            dependencies: ["PianoGraderCore", "PianoGraderIO", "PianoPadState", "PianoLessons", "PianoAI", "EarTrainingUI", "EarTrainingIntegration"]
        ),
        .testTarget(
            name: "PianoGraderCoreTests",
            dependencies: ["PianoGraderCore"]
        ),
        .testTarget(
            name: "PianoPadStateTests",
            dependencies: ["PianoPadState"]
        ),
        .testTarget(
            name: "PianoAITests",
            dependencies: ["PianoAI", "PianoGraderCore"]
        ),
        .testTarget(
            name: "PianoLessonsTests",
            dependencies: ["PianoLessons", "PianoGraderCore"]
        ),
        .target(name: "EarTrainingUI", dependencies: ["PianoGraderCore", "PianoGraderIO"]),
        .target(name: "EarTrainingIntegration", dependencies: ["EarTrainingUI", "PianoPadState", "PianoGraderCore"]),
        .executableTarget(name: "EarTrainer", dependencies: ["EarTrainingUI"]),
        .testTarget(name: "EarTrainingUITests", dependencies: ["EarTrainingUI", "EarTrainingIntegration", "PianoGraderCore", "PianoPadState"]),
    ]
)
