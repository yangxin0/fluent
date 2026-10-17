import Foundation
import os.log

private let log = Logger(subsystem: "com.yangxin.inputmethod.Fluent", category: "rewrite")

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

    /// `configProblem` says why the config file couldn't be used, if so.
    public func textChanged(raw: String, instructions: String, generation: Int, config: AppConfig?,
                            configProblem: String? = nil) {
        task?.cancel()
        task = nil
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return }
        guard let config, config.isConfigured else {
            let reason = configProblem.map { "Config error: \($0)" } ?? "Not configured"
            emit(.failed(generation: generation, message: "\(reason) — IME menu ▸ Open Fluent Settings…"))
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
            // Persisted at default level so `log show` can compare models:
            // time to first token and total time per request.
            let model = config.model
            let started = Date()
            var firstTokenMs: Int?
            func ms(since date: Date) -> Int { Int(Date().timeIntervalSince(date) * 1000) }
            log.notice("request gen=\(generation, privacy: .public) model=\(model, privacy: .public) chars=\(trimmed.count, privacy: .public)")
            var accumulated = ""
            do {
                for try await delta in client.stream(config: config, instructions: instructions, input: trimmed) {
                    if Task.isCancelled { break }
                    if firstTokenMs == nil {
                        firstTokenMs = ms(since: started)
                        log.notice("first token gen=\(generation, privacy: .public) model=\(model, privacy: .public) ttft=\(firstTokenMs!, privacy: .public)ms")
                    }
                    accumulated += delta
                    self?.emit(.delta(generation: generation, accumulated: accumulated))
                }
                if Task.isCancelled {
                    log.notice("cancelled gen=\(generation, privacy: .public) model=\(model, privacy: .public) after=\(ms(since: started), privacy: .public)ms ttft=\(firstTokenMs.map(String.init) ?? "-", privacy: .public)ms")
                    return
                }
                log.notice("done gen=\(generation, privacy: .public) model=\(model, privacy: .public) total=\(ms(since: started), privacy: .public)ms ttft=\(firstTokenMs.map(String.init) ?? "-", privacy: .public)ms out=\(accumulated.count, privacy: .public)")
                self?.emit(.done(generation: generation, text: accumulated))
            } catch is CancellationError {
                log.notice("cancelled gen=\(generation, privacy: .public) model=\(model, privacy: .public) after=\(ms(since: started), privacy: .public)ms")
            } catch let error as URLError where error.code == .cancelled {
                log.notice("cancelled gen=\(generation, privacy: .public) model=\(model, privacy: .public) after=\(ms(since: started), privacy: .public)ms")
            } catch {
                guard !Task.isCancelled else { return }
                log.error("failed gen=\(generation, privacy: .public) model=\(model, privacy: .public) after=\(ms(since: started), privacy: .public)ms: \(Self.humanize(error), privacy: .public)")
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

    public static func humanize(_ error: Error) -> String {
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
