#if canImport(FoundationNetworking)
    import Foundation
    import FoundationNetworking
#else
    import Foundation
#endif
import Testing
@testable import OnetimeSecret

/// Exercises the `URLSession`-backed transport without a network, through a
/// `URLProtocol` stub registered on a private session. Every other suite
/// swaps the transport out; this one proves the default does what the
/// protocol promises: faithful request translation, status codes returned
/// rather than thrown, and failures below HTTP surfaced as errors.
@Suite("URLSessionTransport")
struct TransportTests {
    @Test("translates the request and the response faithfully")
    func roundTrip() async throws {
        let stub = StubHost()
        defer { stub.close() }
        let body = Data(#"{"secret":{"kind":"conceal","secret":"hello"}}"#.utf8)
        let request = TransportRequest(
            method: .post,
            url: stub.url("/api/v2/guest/secret/conceal"),
            headers: ["Content-Type": "application/json", "X-Trace": "abc"],
            body: body,
            timeout: 12
        )
        stub.reply(
            status: 201,
            headers: ["X-Request-Id": "req-1", "Content-Type": "application/json"],
            body: Data("{\"ok\":true}".utf8)
        )

        let response = try await URLSessionTransport(session: stub.session).send(request)

        let received = try #require(stub.received)
        #expect(received.httpMethod == "POST")
        #expect(received.url == request.url)
        #expect(received.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(received.value(forHTTPHeaderField: "X-Trace") == "abc")
        #expect(received.timeoutInterval == 12)
        #expect(received.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(stub.receivedBody == body)

        #expect(response.statusCode == 201)
        #expect(response.header("x-request-id") == "req-1")
        #expect(response.body == Data("{\"ok\":true}".utf8))
    }

    @Test("GET sends no body")
    func getWithoutBody() async throws {
        let stub = StubHost()
        defer { stub.close() }
        stub.reply(status: 200, body: Data("{}".utf8))

        _ = try await URLSessionTransport(session: stub.session)
            .send(TransportRequest(method: .get, url: stub.url("/api/v2/status")))

        #expect(stub.received?.httpMethod == "GET")
        #expect(stub.receivedBody.isEmpty)
    }

    @Test("non-2xx responses are returned, not thrown")
    func errorStatusIsReturned() async throws {
        let stub = StubHost()
        defer { stub.close() }
        stub.reply(status: 404, body: Fixtures.data("error_404"))

        let response = try await URLSessionTransport(session: stub.session)
            .send(TransportRequest(method: .get, url: stub.url("/api/v2/guest/secret/gone")))

        #expect(response.statusCode == 404)
        #expect(String(decoding: response.body, as: UTF8.self).contains("RecordNotFound"))
    }

    @Test("failures below HTTP are thrown and the client wraps them as .transport")
    func connectionFailure() async throws {
        let stub = StubHost()
        defer { stub.close() }
        stub.fail(with: URLError(.cannotConnectToHost))
        let transport = URLSessionTransport(session: stub.session)

        await #expect(throws: (any Error).self) {
            try await transport.send(TransportRequest(method: .get, url: stub.url("/api/v2/status")))
        }

        // Replies are single-use; arm the stub again for the client's request.
        stub.fail(with: URLError(.cannotConnectToHost))
        let client = OnetimeSecretClient(baseURL: stub.url("/"), transport: transport)
        do {
            _ = try await client.system.status()
            Issue.record("Expected an error")
        } catch let error as OnetimeSecretError {
            guard case .transport = error else {
                Issue.record("Expected .transport, got \(error)")
                return
            }
            #expect(error.isRetryable)
        }
    }

    @Test("the client's own headers reach the wire through the default transport")
    func clientThroughURLSession() async throws {
        let stub = StubHost()
        defer { stub.close() }
        stub.reply(status: 200, body: Fixtures.data("system_status"))
        let client = OnetimeSecretClient(
            baseURL: stub.url("/"),
            transport: URLSessionTransport(session: stub.session)
        )

        let status = try await client.system.status()

        #expect(status.isNominal)
        let received = try #require(stub.received)
        #expect(received.url?.path == "/api/v2/status")
        #expect(received.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(received.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("onetimesecret-ios/") == true)
        #expect(received.value(forHTTPHeaderField: "X-Onetime-Client")?.hasPrefix("swift:") == true)
        #expect(received.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("the shared transport uses an ephemeral session without a cache or cookies")
    func sharedSession() {
        let configuration = URLSessionTransport.makeDefaultSession().configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(!configuration.httpShouldSetCookies)
    }
}

/// One stubbed host per test, so tests can run in parallel against the same
/// `URLProtocol` class. The host name is unique and routes to this instance.
final class StubHost: @unchecked Sendable {
    enum Reply {
        case response(status: Int, headers: [String: String], body: Data)
        case failure(any Error)
    }

    let host = "stub-\(UUID().uuidString.lowercased()).invalid"
    let session: URLSession

    private let lock = NSLock()
    private var pending: Reply?
    private(set) var received: URLRequest?
    private(set) var receivedBody = Data()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        StubURLProtocol.register(self, for: host)
    }

    func url(_ path: String) -> URL {
        guard let url = URL(string: "https://\(host)\(path)") else {
            fatalError("Bad stub path \(path)")
        }
        return url
    }

    func reply(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        lock.lock()
        defer { lock.unlock() }
        pending = .response(status: status, headers: headers, body: body)
    }

    func fail(with error: any Error) {
        lock.lock()
        defer { lock.unlock() }
        pending = .failure(error)
    }

    func close() {
        StubURLProtocol.unregister(host)
        session.invalidateAndCancel()
    }

    fileprivate func take(_ request: URLRequest) -> Reply? {
        lock.lock()
        defer { lock.unlock() }
        received = request
        receivedBody = Self.body(of: request)
        let reply = pending
        pending = nil
        return reply
    }

    /// `URLSession` turns `httpBody` into a stream before the protocol sees
    /// the request on Apple platforms; accept either form.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class StubURLProtocol: URLProtocol {
    /// Host name to stub, guarded by a lock because tests run in parallel.
    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var hosts: [String: StubHost] = [:]

        subscript(host: String) -> StubHost? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return hosts[host]
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                hosts[host] = newValue
            }
        }
    }

    private static let registry = Registry()

    static func register(_ stub: StubHost, for host: String) {
        registry[host] = stub
    }

    static func unregister(_ host: String) {
        registry[host] = nil
    }

    private static func stub(for request: URLRequest) -> StubHost? {
        guard let host = request.url?.host else { return nil }
        return registry[host]
    }

    override static func canInit(with request: URLRequest) -> Bool {
        stub(for: request) != nil
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let client else { return }
        guard let url = request.url, let stub = Self.stub(for: request), let reply = stub.take(request) else {
            client.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch reply {
        case let .response(status, headers, body):
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) else {
                client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: body)
            client.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
