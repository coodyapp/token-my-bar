import Foundation
import Testing
@testable import TokenMyBarCore

/// Stateless URLProtocol stub: the response is derived entirely from the URL,
/// so tests stay parallel-safe (no shared mutable responder).
///
/// - `http://stub.test/ok` → 200 `{"ok":true}`
/// - `http://stub.test/malformed` → 200 with non-JSON body
/// - `http://stub.test/status/<code>` → that status, `{}` body
final class StubURLProtocol: URLProtocol {
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "stub.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let status: Int
        let body: Data
        if url.path.hasPrefix("/status/"), let code = Int(url.path.dropFirst("/status/".count)) {
            status = code
            body = Data("{}".utf8)
        } else if url.path == "/malformed" {
            status = 200
            body = Data("not json".utf8)
        } else {
            status = 200
            body = Data(#"{"ok":true}"#.utf8)
        }

        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func httpStatus(of error: Error) -> Int? {
    if case let AuthError.http(code) = error { return code }
    return nil
}

@Test func fetchObjectSucceedsOn200() async throws {
    let object = try await RemoteJSON.fetchObject(
        RemoteJSON.request(url: "http://stub.test/ok"),
        session: StubURLProtocol.makeSession()
    )
    #expect(object["ok"] as? Bool == true)
}

@Test func fetchObjectThrowsHTTPStatusOn401() async {
    do {
        _ = try await RemoteJSON.fetchObject(
            RemoteJSON.request(url: "http://stub.test/status/401"),
            session: StubURLProtocol.makeSession()
        )
        Issue.record("expected a thrown error")
    } catch {
        #expect(httpStatus(of: error) == 401)
    }
}

@Test func fetchObjectThrowsHTTPStatusOnTransient500() async {
    // 500 is transient: one retry happens, then the status surfaces.
    do {
        _ = try await RemoteJSON.fetchObject(
            RemoteJSON.request(url: "http://stub.test/status/500"),
            session: StubURLProtocol.makeSession()
        )
        Issue.record("expected a thrown error")
    } catch {
        #expect(httpStatus(of: error) == 500)
    }
}

@Test func fetchObjectThrowsParseFailedOnMalformedBody() async {
    do {
        _ = try await RemoteJSON.fetchObject(
            RemoteJSON.request(url: "http://stub.test/malformed"),
            session: StubURLProtocol.makeSession()
        )
        Issue.record("expected a thrown error")
    } catch {
        #expect(httpStatus(of: error) == nil) // not an HTTP-status error
    }
}
