import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import WoorisaiAPI

struct WoorisaiAPISecurityTests {
  @Test(arguments: [
    "123",
    "12345",
    "12 3",
    "１２３４",
    "١٢٣٤",
    "12\n3",
  ])
  func rejectsPINsThatAreNotExactlyFourASCIIDigits(pin: String) {
    #expect(throws: ParticipantCredentialError.invalidPIN) {
      try ParticipantCredential(slot: .one, pin: pin)
    }
  }

  @Test
  func credentialDescriptionRedactsPINAndHeader() throws {
    let credential = try ParticipantCredential(slot: .two, pin: "0123")

    #expect(credential.description == "ParticipantCredential(slot: 2, pin: [REDACTED])")
    #expect(!credential.description.contains("0123"))
    #expect(!credential.description.contains("MjowMTIz"))
  }

  @Test
  func credentialStoreLivesOnlyInMemoryAndCanBeCleared() async throws {
    let store = InMemoryCredentialStore()
    #expect(await !store.containsCredential)

    await store.replace(with: try ParticipantCredential(slot: .one, pin: "0123"))
    #expect(await store.containsCredential)

    await store.clear()
    #expect(await !store.containsCredential)
  }

  @Test
  func authorizationPolicyCoversAllGeneratedOperationsExactlyOnce() {
    #expect(APIOperationAuthorizationPolicy.publicOperationIDs.count == 2)
    #expect(APIOperationAuthorizationPolicy.protectedOperationIDs.count == 19)
    #expect(
      APIOperationAuthorizationPolicy.publicOperationIDs.isDisjoint(
        with: APIOperationAuthorizationPolicy.protectedOperationIDs
      ))
    #expect(
      APIOperationAuthorizationPolicy.publicOperationIDs
        .union(APIOperationAuthorizationPolicy.protectedOperationIDs).count == 21
    )
  }

  @Test
  func injectsBasicAuthorizationForProtectedAPIRequest() async throws {
    let store = InMemoryCredentialStore()
    await store.replace(with: try ParticipantCredential(slot: .one, pin: "0123"))
    let middleware = try makeMiddleware(store: store)
    let recorder = RequestRecorder()

    _ = try await middleware.intercept(
      HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/api/v2/relationship-scores"),
      body: nil,
      baseURL: makeURL("https://api.example.test"),
      operationID: "getRelationshipScores"
    ) { request, _, _ in
      await recorder.record(request)
      return (HTTPResponse(status: .ok), nil)
    }

    let request = try #require(await recorder.request)
    #expect(request.headerFields[.authorization] == "Basic MTowMTIz")
  }

  @Test(arguments: ["getHealth", "listLoginOptions"])
  func stripsAuthorizationFromPublicAPIRequests(operationID: String) async throws {
    let store = InMemoryCredentialStore()
    await store.replace(with: try ParticipantCredential(slot: .one, pin: "0123"))
    let middleware = try makeMiddleware(store: store)
    let recorder = RequestRecorder()
    var request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/public")
    request.headerFields[.authorization] = "Basic should-not-leave"

    _ = try await middleware.intercept(
      request,
      body: nil,
      baseURL: makeURL("https://api.example.test"),
      operationID: operationID
    ) { request, _, _ in
      await recorder.record(request)
      return (HTTPResponse(status: .ok), nil)
    }

    let recordedRequest = try #require(await recorder.request)
    #expect(recordedRequest.headerFields[.authorization] == nil)
  }

  @Test
  func refusesProtectedRequestWhenCredentialIsMissing() async throws {
    let middleware = try makeMiddleware(store: InMemoryCredentialStore())

    await #expect(throws: APIAuthorizationMiddlewareError.credentialMissing) {
      _ = try await middleware.intercept(
        HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/api/v2/media-uploads"),
        body: nil,
        baseURL: makeURL("https://api.example.test"),
        operationID: "initiateMediaUpload"
      ) { _, _, _ in
        Issue.record("A credential-less protected request reached the transport")
        return (HTTPResponse(status: .ok), nil)
      }
    }
  }

  @Test
  func refusesCredentialInjectionForAnotherOrigin() async throws {
    let store = InMemoryCredentialStore()
    await store.replace(with: try ParticipantCredential(slot: .one, pin: "0123"))
    let middleware = try makeMiddleware(store: store)

    await #expect(throws: APIAuthorizationMiddlewareError.untrustedOrigin) {
      _ = try await middleware.intercept(
        HTTPRequest(method: .put, scheme: nil, authority: nil, path: "/presigned-upload"),
        body: nil,
        baseURL: makeURL("https://r2.example.test"),
        operationID: "initiateMediaUpload"
      ) { request, _, _ in
        Issue.record(
          "An API credential reached another origin: \(String(describing: request.headerFields[.authorization]))"
        )
        return (HTTPResponse(status: .ok), nil)
      }
    }
  }

  @Test
  func redirectPolicyStripsAuthorizationAndRejectsUntrustedDestinations() throws {
    let origin = try #require(APIOrigin(url: makeURL("https://api.example.test")))
    let delegate = SameOriginRedirectDelegate(apiOrigin: origin)
    var sameOrigin = URLRequest(url: makeURL("https://api.example.test/next"))
    sameOrigin.setValue("Basic must-not-follow", forHTTPHeaderField: "Authorization")

    let sanitized = try #require(delegate.sanitizedRedirectRequest(sameOrigin))
    #expect(sanitized.url == sameOrigin.url)
    #expect(sanitized.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(
      delegate.sanitizedRedirectRequest(
        URLRequest(url: makeURL("https://r2.example.test/next"))
      ) == nil
    )
    #expect(
      delegate.sanitizedRedirectRequest(
        URLRequest(url: makeURL("http://api.example.test/next"))
      ) == nil
    )
  }

  @Test
  func transportDoesNotRetainCookiesCacheOrURLCredentials() {
    let configuration = WoorisaiAPITransportFactory.makeSessionConfiguration()

    #expect(configuration.httpCookieStorage == nil)
    #expect(!configuration.httpShouldSetCookies)
    #expect(configuration.urlCache == nil)
    #expect(configuration.urlCredentialStorage == nil)
    #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
  }

  private func makeMiddleware(
    store: InMemoryCredentialStore
  ) throws -> BasicAuthorizationMiddleware {
    let baseURL = makeURL("https://api.example.test")
    return BasicAuthorizationMiddleware(
      apiOrigin: try #require(APIOrigin(url: baseURL)),
      credentialStore: store
    )
  }
}

private func makeURL(_ value: String) -> URL {
  guard let url = URL(string: value) else {
    preconditionFailure("Invalid static test URL")
  }
  return url
}

private actor RequestRecorder {
  private(set) var request: HTTPRequest?

  func record(_ request: HTTPRequest) {
    self.request = request
  }
}
