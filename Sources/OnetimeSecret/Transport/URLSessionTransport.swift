#if canImport(FoundationNetworking)
    import Foundation
    public import FoundationNetworking
#else
    public import Foundation
#endif

/// The default ``HTTPTransport``, backed by `URLSession`.
public struct URLSessionTransport: HTTPTransport {
    /// The instance every client uses unless told otherwise. One session,
    /// one connection pool, however many clients an app creates.
    public static let shared = URLSessionTransport(session: makeDefaultSession())

    private let session: URLSession

    /// Creates a transport around your own session.
    ///
    /// Prefer ``shared`` unless you need a delegate, a proxy, or pinning.
    /// If the session you pass has a `URLCache`, responses that carry a
    /// secret value (reveal, and the first receipt fetch of a generated
    /// secret) can end up in that cache; the SDK sets
    /// `reloadIgnoringLocalCacheData`, which only governs reads. Use a
    /// configuration with `urlCache = nil`, as ``makeDefaultSession()`` does.
    public init(session: URLSession) {
        self.session = session
    }

    /// An ephemeral session with caching and cookies disabled.
    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        #if !canImport(FoundationNetworking)
            configuration.waitsForConnectivity = false
        #endif
        return URLSession(configuration: configuration)
    }

    public func send(_ request: TransportRequest) async throws -> TransportResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String {
                headers[name] = value
            }
        }
        return TransportResponse(statusCode: http.statusCode, headers: headers, body: data)
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        #if canImport(FoundationNetworking)
            // swift-corelibs-foundation: bridge the completion-handler API and
            // honour task cancellation.
            let box = TaskBox()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let task = session.dataTask(with: request) { data, response, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let data, let response {
                            continuation.resume(returning: (data, response))
                        } else {
                            continuation.resume(throwing: URLError(.badServerResponse))
                        }
                    }
                    box.start(task)
                }
            } onCancel: {
                box.cancel()
            }
        #else
            return try await session.data(for: request)
        #endif
    }
}

#if canImport(FoundationNetworking)
    /// Holds a data task so that it can be cancelled from the cancellation
    /// handler, which may run before the task has been created.
    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDataTask?
        private var cancelled = false

        func start(_ task: URLSessionDataTask) {
            lock.lock()
            self.task = task
            let cancelled = cancelled
            lock.unlock()
            if cancelled {
                task.cancel()
            } else {
                task.resume()
            }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let task = task
            lock.unlock()
            task?.cancel()
        }
    }
#endif
