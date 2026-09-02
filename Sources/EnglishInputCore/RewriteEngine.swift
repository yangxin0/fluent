import Foundation

/// Debounces keystrokes into at most one in-flight LLM request, cancelling
/// stale ones. Callbacks are delivered on the main queue; the generation
/// number lets the caller drop updates from superseded requests.
public final class RewriteEngine {
    public enum Update {
        case began(generation: Int)
        case delta(generation: Int, accumulated: String)
        case done(generation: Int, text: String)
        case failed(generation: Int, message: String)
    }

    public var onUpdate: ((Update) -> Void)?

    private let client: ResponsesClient
    private var task: Task<Void, Never>?

    public init(client: ResponsesClient = ResponsesClient()) {
        self.client = client
    }

    public func textChanged(raw: String, instructions: String, generation: Int, config: AppConfig?) {
        task?.cancel()
        task = nil
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return }
        guard let config, config.isConfigured else {
            emit(.failed(generation: generation,
                         message: "Not configured — IME menu ▸ Open Config File"))
            return
        }
        let client = self.client
        task = Task { [weak self] in
            do {
                let debounceMs = AppConfig.clampDebounce(config.debounceMs)
                try await Task.sleep(nanoseconds: UInt64(debounceMs) * 1_000_000)
            } catch { return }
            guard !Task.isCancelled else { return }
            self?.emit(.began(generation: generation))
            var accumulated = ""
            do {
                for try await delta in client.stream(config: config, instructions: instructions, input: raw) {
                    if Task.isCancelled { return }
                    accumulated += delta
                    self?.emit(.delta(generation: generation, accumulated: accumulated))
                }
                guard !Task.isCancelled else { return }
                self?.emit(.done(generation: generation, text: accumulated))
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                guard !Task.isCancelled else { return }
                self?.emit(.failed(generation: generation, message: Self.humanize(error)))
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    private func emit(_ update: Update) {
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(update)
        }
    }

    static func humanize(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed:
                return "offline"
            case .timedOut:
                return "timed out"
            default:
                return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
