import Foundation
@testable import OnetimeSecret

/// A transport that replays canned responses and records what it was asked
/// to send. Thread-safe so that it can be shared with the client under test.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    enum Reply: Sendable {
        case response(TransportResponse)
        case failure(any Error)
    }

    private let lock = NSLock()
    private var queue: [Reply]
    private(set) var requests: [TransportRequest] = []

    init(_ replies: [Reply] = []) {
        queue = replies
    }

    convenience init(status: Int = 200, fixture: String, headers: [String: String] = [:]) {
        self.init([.response(TransportResponse(statusCode: status, headers: headers, body: Fixtures.data(fixture)))])
    }

    convenience init(status: Int, json: String, headers: [String: String] = [:]) {
        self.init([.response(TransportResponse(statusCode: status, headers: headers, body: Data(json.utf8)))])
    }

    func enqueue(_ reply: Reply) {
        lock.lock()
        defer { lock.unlock() }
        queue.append(reply)
    }

    func enqueue(status: Int = 200, fixture: String) {
        enqueue(.response(TransportResponse(statusCode: status, body: Fixtures.data(fixture))))
    }

    private func dequeue(recording request: TransportRequest) -> Reply? {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        return queue.isEmpty ? nil : queue.removeFirst()
    }

    func send(_ request: TransportRequest) async throws -> TransportResponse {
        guard let reply = dequeue(recording: request) else {
            fatalError("MockTransport: no reply queued for \(request.method.rawValue) \(request.url)")
        }
        switch reply {
        case let .response(response):
            return response
        case let .failure(error):
            throw error
        }
    }

    var lastRequest: TransportRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.last
    }
}

enum Fixtures {
    static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            fatalError("Missing fixture \(name).json")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            fatalError("Unreadable fixture \(name).json: \(error)")
        }
    }
}

extension TransportRequest {
    /// The JSON body as a dictionary, for assertions.
    var jsonBody: [String: Any]? {
        guard let body else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }
}

extension OnetimeSecretClient {
    static func guest(_ transport: MockTransport, shareDomain: String? = nil) -> OnetimeSecretClient {
        OnetimeSecretClient(
            configuration: Configuration(region: .unitedStates, shareDomain: shareDomain),
            transport: transport
        )
    }

    static func authenticated(_ transport: MockTransport) -> OnetimeSecretClient {
        OnetimeSecretClient(
            configuration: Configuration(
                region: .europe,
                credentials: Credentials(username: "user@example.com", apiToken: "tok_123")
            ),
            transport: transport
        )
    }
}
