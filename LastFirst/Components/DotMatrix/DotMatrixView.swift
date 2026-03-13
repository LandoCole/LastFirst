import SwiftUI
import SpriteKit

struct DotMatrixView: UIViewRepresentable {
    @ObservedObject var statsVM: ReadingStatsViewModel

    func makeUIView(context: Context) -> SKView {
        let skView = SKView()
        skView.backgroundColor = .clear
        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true
        return skView
    }

    func updateUIView(_ skView: SKView, context: Context) {
        let coordinator = context.coordinator

        if coordinator.scene == nil {
            // Defer scene setup until layout pass provides valid size
            DispatchQueue.main.async {
                guard skView.bounds.width > 0, skView.bounds.height > 0 else { return }
                guard coordinator.scene == nil else { return }

                let scene = DotGridScene(size: skView.bounds.size)
                scene.scaleMode = .resizeFill
                skView.presentScene(scene)
                coordinator.scene = scene

                // Generate initial stats and play entrance
                coordinator.updateStats(from: statsVM)
                scene.playEntranceAnimation { [weak coordinator] in
                    guard let coordinator else { return }
                    // Apply first frame after entrance
                    if let firstFrame = coordinator.currentFrames.first {
                        scene.applyFrame(firstFrame, animated: true)
                    }
                    coordinator.startRotationTimer()
                }
            }
        } else {
            coordinator.updateStats(from: statsVM)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    class Coordinator {
        var scene: DotGridScene?
        var currentFrames: [DotFrame] = []
        var currentIndex = 0
        var rotationTimer: Timer?
        private var lastStatsHash: Int = 0

        func updateStats(from statsVM: ReadingStatsViewModel) {
            let hash = computeHash(from: statsVM)
            guard hash != lastStatsHash else { return }
            lastStatsHash = hash

            let displays = DotMatrixStatsRenderer.generateStatDisplays(from: statsVM)
            currentFrames = displays.map { DotMatrixStatsRenderer.renderStatToFrame($0) }
            currentIndex = 0

            if let scene, let firstFrame = currentFrames.first {
                scene.applyFrame(firstFrame, animated: true)
            }
        }

        func startRotationTimer() {
            rotationTimer?.invalidate()
            let timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.rotateToNextStat()
                }
            }
            rotationTimer = timer
        }

        func stopRotationTimer() {
            rotationTimer?.invalidate()
            rotationTimer = nil
        }

        private func rotateToNextStat() {
            guard currentFrames.count > 1, let scene else { return }
            currentIndex = (currentIndex + 1) % currentFrames.count
            let nextFrame = currentFrames[currentIndex]
            scene.transitionToFrame(nextFrame, style: .decayRegrow)
        }

        private func computeHash(from statsVM: ReadingStatsViewModel) -> Int {
            var hasher = Hasher()
            hasher.combine(statsVM.todayReadingSeconds)
            hasher.combine(statsVM.todayWPM)
            hasher.combine(statsVM.statsCache?.currentStreak ?? 0)
            hasher.combine(statsVM.statsCache?.totalWordsRead ?? 0)
            return hasher.finalize()
        }

    }

    static func dismantleUIView(_ uiView: SKView, coordinator: Coordinator) {
        coordinator.stopRotationTimer()
    }
}
