import Foundation

/// Keeps one console's Integration API event stream open and hands every
/// message to `onMessage`. Reconnects with a capped backoff: the controller
/// drops the socket on restarts and firmware updates, and an unreachable
/// console must not be hammered.
@MainActor
final class ProtectEventStream {
    private weak var service: ProtectService?
    private let onMessage: (Data) -> Void
    private var task: Task<Void, Never>?

    init(service: ProtectService, onMessage: @escaping (Data) -> Void) {
        self.service = service
        self.onMessage = onMessage
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Drop the current socket and connect again (address or API key changed).
    func restart() {
        stop()
        start()
    }

    private func run() async {
        var backoff: Double = 2
        while !Task.isCancelled {
            if let socket = service?.makeEventSocket() {
                socket.resume()
                RTSPClient.log("[Events] connecting")
                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        backoff = 2
                        switch message {
                        case .data(let data): onMessage(data)
                        case .string(let text): onMessage(Data(text.utf8))
                        @unknown default: break
                        }
                    }
                } catch {
                    RTSPClient.log("[Events] socket closed: \(error.localizedDescription)")
                }
                socket.cancel(with: .goingAway, reason: nil)
            }
            do {
                try await Task.sleep(for: .seconds(backoff))
            } catch {
                return
            }
            backoff = min(backoff * 2, 60)
        }
    }
}
