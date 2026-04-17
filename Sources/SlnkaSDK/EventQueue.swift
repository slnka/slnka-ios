import Foundation

/// Offline-capable event queue with automatic batch flushing.
///
/// Features:
/// - In-memory buffer with configurable flush threshold
/// - Automatic periodic flushing on a timer
/// - Persistent retry queue for failed events (UserDefaults)
/// - Thread-safe access via DispatchQueue
/// - Manual flush support
final class EventQueue {

    private let transport: Transport
    private let config: SlnkaConfig
    private let storage: SlnkaStorage
    private let debug: Bool

    /// In-memory event buffer (thread-safe via `lock`).
    private var buffer: [SlnkaEvent] = []

    /// Lock for thread-safe buffer access.
    private let lock = DispatchQueue(label: "ma.slnka.sdk.eventqueue")

    /// Timer for periodic flushing.
    private var flushTimer: DispatchSourceTimer?

    /// Whether a flush is currently in progress.
    private var isFlushing = false

    /// Workspace ID for batch header.
    private var workspaceId: String?

    // MARK: - Init

    init(transport: Transport, config: SlnkaConfig, storage: SlnkaStorage) {
        self.transport = transport
        self.config = config
        self.storage = storage
        self.debug = config.debug

        startFlushTimer()
        loadRetryQueue()
    }

    deinit {
        flushTimer?.cancel()
    }

    // MARK: - Configuration

    /// Sets the workspace ID to include in batch requests.
    func setWorkspaceId(_ workspaceId: String?) {
        self.workspaceId = workspaceId
    }

    // MARK: - Enqueue

    /// Adds an event to the queue. Triggers auto-flush if the buffer reaches `flushSize`.
    func enqueue(_ event: SlnkaEvent) {
        lock.sync {
            buffer.append(event)
            logDebug("Enqueued event: \(event.eventName) (buffer: \(buffer.count)/\(config.flushSize))")
        }

        // Check if we should auto-flush
        let shouldFlush = lock.sync { buffer.count >= config.flushSize }
        if shouldFlush {
            logDebug("Buffer full, triggering auto-flush")
            flush()
        }
    }

    // MARK: - Flush

    /// Flushes all buffered events to the server.
    /// Events that fail to send are persisted for later retry.
    func flush() {
        let eventsToSend: [SlnkaEvent] = lock.sync {
            guard !buffer.isEmpty && !isFlushing else { return [] }
            isFlushing = true
            let events = buffer
            buffer.removeAll()
            return events
        }

        guard !eventsToSend.isEmpty else {
            lock.sync { isFlushing = false }
            return
        }

        logDebug("Flushing \(eventsToSend.count) events")

        Task {
            await sendBatch(eventsToSend)
            lock.sync { isFlushing = false }
        }
    }

    /// Async variant of flush that waits for completion.
    func flushAsync() async {
        let eventsToSend: [SlnkaEvent] = lock.sync {
            guard !buffer.isEmpty && !isFlushing else { return [] }
            isFlushing = true
            let events = buffer
            buffer.removeAll()
            return events
        }

        guard !eventsToSend.isEmpty else {
            lock.sync { isFlushing = false }
            return
        }

        logDebug("Flushing \(eventsToSend.count) events (async)")
        await sendBatch(eventsToSend)
        lock.sync { isFlushing = false }
    }

    /// Returns the number of events currently in the buffer.
    var pendingCount: Int {
        lock.sync { buffer.count }
    }

    // MARK: - Batch Sending

    private func sendBatch(_ events: [SlnkaEvent]) async {
        // Split into chunks of 100 (server max batch size)
        let chunks = stride(from: 0, to: events.count, by: 100).map {
            Array(events[$0..<min($0 + 100, events.count)])
        }

        for chunk in chunks {
            var retriesRemaining = config.maxRetries

            while retriesRemaining > 0 {
                do {
                    let response = try await transport.sendBatch(chunk, workspaceId: workspaceId)

                    if response.success {
                        logDebug("Batch sent successfully (\(chunk.count) events)")
                        break
                    }

                    if !response.retryable {
                        logDebug("Batch rejected (non-retryable), dropping \(chunk.count) events")
                        break
                    }

                    // Retryable error
                    retriesRemaining -= 1
                    if retriesRemaining > 0 {
                        let delay = retryDelay(attempt: config.maxRetries - retriesRemaining)
                        logDebug("Retrying in \(delay)s (\(retriesRemaining) retries remaining)")
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                } catch {
                    retriesRemaining -= 1
                    logDebug("Batch send error: \(error.localizedDescription)")

                    if retriesRemaining > 0 {
                        let delay = retryDelay(attempt: config.maxRetries - retriesRemaining)
                        logDebug("Retrying in \(delay)s (\(retriesRemaining) retries remaining)")
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
            }

            // If all retries exhausted, persist events for later retry
            if retriesRemaining == 0 {
                logDebug("All retries exhausted, persisting \(chunk.count) events for later retry")
                storage.storeFailedEvents(chunk)
            }
        }
    }

    // MARK: - Retry Queue

    /// Loads previously failed events from persistent storage and adds them to the buffer.
    private func loadRetryQueue() {
        let failedEvents = storage.loadAndClearFailedEvents()
        if !failedEvents.isEmpty {
            lock.sync {
                buffer.append(contentsOf: failedEvents)
            }
            logDebug("Loaded \(failedEvents.count) events from retry queue")
        }
    }

    // MARK: - Flush Timer

    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        let intervalSeconds = Double(config.flushIntervalMs) / 1000.0
        timer.schedule(
            deadline: .now() + intervalSeconds,
            repeating: intervalSeconds,
            leeway: .seconds(1)
        )
        timer.setEventHandler { [weak self] in
            self?.flush()
        }
        timer.resume()
        flushTimer = timer
    }

    // MARK: - Helpers

    /// Calculates exponential backoff delay with jitter.
    private func retryDelay(attempt: Int) -> Double {
        let base = 1.0
        let maxDelay = 30.0
        let exponential = min(base * pow(2.0, Double(attempt)), maxDelay)
        let jitter = Double.random(in: 0...(exponential * 0.1))
        return exponential + jitter
    }

    private func logDebug(_ message: String) {
        if debug {
            print("[SlnkaSDK:EventQueue] \(message)")
        }
    }
}
