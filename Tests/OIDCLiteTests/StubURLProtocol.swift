import Foundation
import Synchronization

class StubURLProtocol: URLProtocol {
    private struct State {
        var responses: [(HTTPURLResponse, Data)] = []
        var requests: [URLRequest] = []
    }

    private static let state = Mutex(State())

    static var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    static func session(responses: [(HTTPURLResponse, Data)]) -> URLSession {
        state.withLock {
            $0.responses = responses
            $0.requests = []
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var capturedRequest = request
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 1024)
                guard count > 0 else { break }
                body.append(buffer, count: count)
            }
            capturedRequest.httpBody = body
        }
        guard let (response, data) = Self.state.withLock({ state in
            state.requests.append(capturedRequest)
            return state.responses.isEmpty ? nil : state.responses.removeFirst()
        }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
