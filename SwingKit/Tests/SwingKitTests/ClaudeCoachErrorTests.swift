// WS-B: a network failure must surface its underlying cause, not an opaque "request failed",
// and must never leak the API key (which lives in a header, never the error message).
import XCTest
@testable import SwingKit

/// A URLProtocol that fails every request with a fixed error — lets us drive ClaudeCoach's
/// catch path offline, without a real network call.
private final class FailingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var failure: Error =
        NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                userInfo: [NSLocalizedDescriptionKey: "The request timed out."])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: Self.failure) }
    override func stopLoading() {}
}

private struct StaticKeyProvider: APIKeyProvider {
    let key: String
    func apiKey() -> String? { key }
}

final class ClaudeCoachErrorTests: XCTestCase {

    /// The default timeout is the real 45s, not the old 8s that killed legitimate Opus calls.
    func testDefaultTimeoutIsFortyFive() {
        XCTAssertEqual(ClaudeCoach().timeout, 45)
    }

    private func failingSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailingURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testNetworkErrorSurfacesUnderlyingCause() async {
        let coach = ClaudeCoach(apiKeyProvider: StaticKeyProvider(key: "test-key-not-real"),
                                session: failingSession(), timeout: 5)
        let report = CoachingRuleBasedTestsSupport.minimalReport()
        do {
            _ = try await coach.coach(report, context: .init())
            XCTFail("expected a CoachingError.network")
        } catch let error as CoachingError {
            let message = "\(error)"
            XCTAssertTrue(message.contains("timed out"),
                          "underlying cause not surfaced, got: \(message)")
            XCTAssertFalse(message.contains("test-key-not-real"), "error must not leak the API key")
        } catch {
            XCTFail("expected CoachingError, got \(error)")
        }
    }
}
