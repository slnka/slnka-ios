import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// In-memory queue dedicated to **mobile behavior events** (taps, scroll-depth,
/// rage taps).
///
/// Design notes (mirror of the Android SDK `BehaviorEventQueue`):
/// - Kept **separate** from `EventQueue` (business events) so that high-volume
///   tap streams cannot starve identify / track / conversion ingestion.
/// - Backed by a serial `DispatchQueue` to keep the SDK dependency-free
///   (no Combine, no async actor required) and compatible with iOS 15.
/// - Drops the **oldest** event when ``SlnkaConfig/behaviorMaxQueueSize`` is
///   reached. Backpressure on a UI-thread tap stream must never block the user.
/// - On HTTP failure the batch is silently dropped (vs. business events which
///   are persisted to disk for retry). Behavior events are statistical signals;
///   losing a small batch is acceptable and prevents unbounded `UserDefaults`
///   growth on long-offline devices.
internal final class BehaviorEventQueue: @unchecked Sendable {

    private let transport: Transport
    private let batchSize: Int
    private let flushIntervalMs: Int
    private let maxQueueSize: Int
    private let debug: Bool

    /// Serial dispatch queue protecting `buffer` and orchestrating flushes.
    private let queue = DispatchQueue(label: "ma.slnka.behavior", qos: .utility)

    /// Internal buffer (only mutated from `queue`).
    private var buffer: [MobileBehaviorEvent] = []

    /// Re-entrancy guard for `performFlush`.
    private var isFlushing = false

    /// Periodic flush timer. Lives on the main run-loop (cheap, very low rate).
    private var flushTimer: Timer?

    /// Lifecycle observer tokens, kept alive for the queue's lifetime.
    private var observers: [NSObjectProtocol] = []

    init(
        transport: Transport,
        batchSize: Int,
        flushIntervalMs: Int,
        maxQueueSize: Int,
        debug: Bool
    ) {
        self.transport = transport
        self.batchSize = batchSize
        self.flushIntervalMs = flushIntervalMs
        self.maxQueueSize = maxQueueSize
        self.debug = debug

        startPeriodicFlush()
        observeAppLifecycle()
    }

    deinit {
        flushTimer?.invalidate()
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Public API

    /// Enqueue a behavior event. Non-blocking; drops oldest on overflow.
    func emit(_ event: MobileBehaviorEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(event)

            if self.buffer.count > self.maxQueueSize {
                let overflow = self.buffer.count - self.maxQueueSize
                self.logDebug("Behavior queue full (\(self.maxQueueSize)), dropping \(overflow) oldest")
                self.buffer.removeFirst(overflow)
            }

            if self.buffer.count >= self.batchSize {
                self.performFlushLocked()
            }
        }
    }

    /// Manually trigger a flush (e.g., on app background).
    func flush() {
        queue.async { [weak self] in
            self?.performFlushLocked()
        }
    }

    /// Number of pending events (useful for tests and debug logs).
    func pendingCount() -> Int {
        queue.sync { buffer.count }
    }

    // MARK: - Internal

    private func performFlushLocked() {
        guard !isFlushing else {
            logDebug("Behavior flush already in progress, skipping")
            return
        }
        guard !buffer.isEmpty else { return }

        isFlushing = true
        let take = min(batchSize, buffer.count)
        let batch = Array(buffer.prefix(take))
        buffer.removeFirst(take)

        // Hand the batch to URLSession via Transport. Capture into a Task to
        // bridge into the async transport API. Failure → drop (statistical
        // signals only, see class kdoc).
        if #available(iOS 15.0, macOS 12.0, *) {
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.transport.sendMobileBehaviorBatch(batch)
                    self.logDebug("Sent behavior batch of \(batch.size) events")
                } catch {
                    self.logDebug("Behavior batch failed: \(error.localizedDescription) (\(batch.size) events dropped)")
                }
                self.queue.async { self.isFlushing = false }
            }
        } else {
            // iOS 13/14 are below the package's minimum platform (iOS 15) so
            // this branch is unreachable in practice — kept for completeness.
            isFlushing = false
        }
    }

    private func startPeriodicFlush() {
        let interval = TimeInterval(flushIntervalMs) / 1000.0
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushTimer = Timer.scheduledTimer(
                withTimeInterval: interval,
                repeats: true
            ) { [weak self] _ in
                self?.flush()
            }
        }
        logDebug("Behavior queue started (batchSize=\(batchSize), flushInterval=\(flushIntervalMs)ms)")
    }

    private func observeAppLifecycle() {
        #if canImport(UIKit)
        let token = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flush()
        }
        observers.append(token)
        #endif
    }

    private func logDebug(_ message: String) {
        if debug { print("[SlnkaSDK:Behavior] \(message)") }
    }
}

// MARK: - Array helper

private extension Array {
    /// Inline `size` accessor to keep the parity with the Android log line
    /// using `batch.size` — pure aesthetic helper.
    var size: Int { count }
}
