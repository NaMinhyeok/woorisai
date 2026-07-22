import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import WoorisaiAPI

struct WoorisaiCredentialValidationTests {
  @Test(arguments: [
    "2026-07-22T07:10:06Z",
    "2026-07-22T07:10:06.123456Z",
  ])
  func decodesSpringInstantFromTheRealGeneratedClientWirePath(
    updatedAt: String
  ) async throws {
    let baseURL = try #require(URL(string: "https://api.example.test"))
    let client = try WoorisaiAPIClient(
      baseURL: baseURL,
      transport: RelationshipScoresWireTransport(updatedAt: updatedAt)
    )

    let participant = try await client.validateCredential(
      ParticipantCredential(slot: .one, pin: "0123")
    )

    #expect(participant == AuthenticatedParticipant(slot: .one, displayName: "봄"))
  }

  @Test
  func validatesCredentialWithProtectedReadAndReturnsAppOwnedParticipant() async throws {
    let store = InMemoryCredentialStore()
    let client = WoorisaiAPIClient(
      credentialValidationClient: CredentialValidationAPIStub(output: makeSuccessOutput(slot: ._1)),
      credentialStore: store
    )

    let participant = try await client.validateCredential(
      ParticipantCredential(slot: .one, pin: "0123")
    )

    #expect(participant == AuthenticatedParticipant(slot: .one, displayName: "봄"))
    #expect(await store.containsCredential)
  }

  @Test
  func mapsUnauthorizedToCredentialRejectedAndClearsRejectedCredential() async throws {
    let store = InMemoryCredentialStore()
    let client = WoorisaiAPIClient(
      credentialValidationClient: CredentialValidationAPIStub(output: makeUnauthorizedOutput()),
      credentialStore: store
    )

    await #expect(throws: WoorisaiAPIError.credentialRejected) {
      _ = try await client.validateCredential(
        ParticipantCredential(slot: .one, pin: "9999")
      )
    }
    #expect(await !store.containsCredential)
  }

  @Test
  func mapsProtectedReadForbiddenWithoutDiscardingValidCredential() async throws {
    let store = InMemoryCredentialStore()
    let client = WoorisaiAPIClient(
      credentialValidationClient: CredentialValidationAPIStub(output: makeForbiddenOutput()),
      credentialStore: store
    )

    await #expect(throws: WoorisaiAPIError.forbidden) {
      _ = try await client.validateCredential(
        ParticipantCredential(slot: .one, pin: "0123")
      )
    }
    #expect(await store.containsCredential)
  }

  @Test(arguments: [
    "AUTHENTICATION_UNAVAILABLE",
    "RELATIONSHIP_UNAVAILABLE",
  ])
  func mapsProtectedReadServiceFailures(errorCode: String) async throws {
    let client = WoorisaiAPIClient(
      credentialValidationClient: CredentialValidationAPIStub(
        output: makeServiceUnavailableOutput(errorCode: errorCode)
      )
    )

    await #expect(throws: WoorisaiAPIError.serviceUnavailable) {
      _ = try await client.validateCredential(
        ParticipantCredential(slot: .two, pin: "0123")
      )
    }
  }

  @Test
  func rejectsSuccessThatDoesNotIdentifyTheSelectedSlot() async throws {
    let client = WoorisaiAPIClient(
      credentialValidationClient: CredentialValidationAPIStub(output: makeSuccessOutput(slot: ._2))
    )

    await #expect(throws: WoorisaiAPIError.schemaDrift) {
      _ = try await client.validateCredential(
        ParticipantCredential(slot: .one, pin: "0123")
      )
    }
  }

  @Test
  func lateCancelledValidationCannotClearNewCredential() async throws {
    let store = InMemoryCredentialStore()
    let api = OverlappingCredentialValidationAPIStub()
    let client = WoorisaiAPIClient(
      credentialValidationClient: api,
      credentialStore: store
    )
    // Equal credential values still represent distinct validation attempts. The late cleanup for
    // the first attempt must not clear the second attempt's newer store revision.
    let oldCredential = try ParticipantCredential(slot: .two, pin: "2222")
    let newCredential = try ParticipantCredential(slot: .two, pin: "2222")

    let oldValidation = Task {
      try await client.validateCredential(oldCredential)
    }
    await credentialExpectEventually { await api.requestCount == 1 }
    oldValidation.cancel()

    let newValidation = Task {
      try await client.validateCredential(newCredential)
    }
    await credentialExpectEventually { await api.requestCount == 2 }
    await api.succeed(request: 1, output: makeSuccessOutput(slot: ._2))
    #expect(try await newValidation.value == .init(slot: .two, displayName: "봄"))

    await api.failWithClientCancellation(request: 0)
    do {
      _ = try await oldValidation.value
      Issue.record("Expected the old validation to stay cancelled")
    } catch is CancellationError {
      // Expected.
    }

    let originURL = try #require(URL(string: "https://api.example.test"))
    let origin = try #require(APIOrigin(url: originURL))
    let middleware = BasicAuthorizationMiddleware(apiOrigin: origin, credentialStore: store)
    let recorder = CredentialHeaderRecorder()
    _ = try await middleware.intercept(
      HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/api/v2/relationship-scores"),
      body: nil,
      baseURL: originURL,
      operationID: "getRelationshipScores"
    ) { request, _, _ in
      await recorder.record(request.headerFields[.authorization])
      return (HTTPResponse(status: .ok), nil)
    }
    #expect(await recorder.authorization == "Basic MjoyMjIy")
  }
}

private struct RelationshipScoresWireTransport: ClientTransport {
  let updatedAt: String

  func send(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String
  ) async throws -> (HTTPResponse, HTTPBody?) {
    guard operationID == "getRelationshipScores",
      request.headerFields[.authorization] == "Basic MTowMTIz"
    else {
      throw RelationshipScoresWireTransportError.unexpectedRequest
    }

    let responseBody = """
      {
        "self":{"slot":1,"displayName":"봄","mine":true},
        "partner":{"slot":2,"displayName":"여름","mine":false},
        "outgoing":{
          "sourceParticipant":{"slot":1,"displayName":"봄","mine":true},
          "targetParticipant":{"slot":2,"displayName":"여름","mine":false},
          "currentScore":50,
          "updatedAt":"\(updatedAt)"
        },
        "incoming":{
          "sourceParticipant":{"slot":2,"displayName":"여름","mine":false},
          "targetParticipant":{"slot":1,"displayName":"봄","mine":true},
          "currentScore":60,
          "updatedAt":"\(updatedAt)"
        }
      }
      """

    return (
      HTTPResponse(
        status: .ok,
        headerFields: [
          .cacheControl: "no-store",
          .contentType: "application/json",
        ]
      ),
      HTTPBody(responseBody)
    )
  }
}

private enum RelationshipScoresWireTransportError: Error {
  case unexpectedRequest
}

private struct CredentialValidationAPIStub: CredentialValidationAPIProtocol {
  let output: Operations.GetRelationshipScores.Output

  func getRelationshipScores(
    _ input: Operations.GetRelationshipScores.Input
  ) async throws -> Operations.GetRelationshipScores.Output {
    output
  }
}

private actor OverlappingCredentialValidationAPIStub: CredentialValidationAPIProtocol {
  private var continuations:
    [Int: CheckedContinuation<Operations.GetRelationshipScores.Output, any Error>] = [:]
  private(set) var requestCount = 0

  func getRelationshipScores(
    _ input: Operations.GetRelationshipScores.Input
  ) async throws -> Operations.GetRelationshipScores.Output {
    let request = requestCount
    requestCount += 1
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        continuations[request] = continuation
      }
    } onCancel: {
      // Complete late to exercise race-safe credential cleanup in the adapter.
    }
  }

  func succeed(request: Int, output: Operations.GetRelationshipScores.Output) {
    continuations.removeValue(forKey: request)?.resume(returning: output)
  }

  func failWithClientCancellation(request: Int) {
    let input = Operations.GetRelationshipScores.Input()
    continuations.removeValue(forKey: request)?.resume(
      throwing: ClientError(
        operationID: "getRelationshipScores",
        operationInput: input,
        causeDescription: "Synthetic late cancellation",
        underlyingError: CancellationError()
      )
    )
  }
}

private actor CredentialHeaderRecorder {
  private(set) var authorization: String?

  func record(_ authorization: String?) {
    self.authorization = authorization
  }
}

private func credentialExpectEventually(
  _ condition: @escaping @Sendable () async -> Bool,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  for _ in 0..<200 {
    if await condition() { return }
    try? await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("검증 요청이 제한 시간 안에 시작되지 않았습니다.", sourceLocation: sourceLocation)
}

private func makeSuccessOutput(
  slot: Components.Schemas.RelationshipParticipant.SlotPayload
) -> Operations.GetRelationshipScores.Output {
  let selfParticipant = Components.Schemas.RelationshipParticipant(
    slot: slot,
    displayName: "봄",
    mine: true
  )
  let partnerSlot: Components.Schemas.RelationshipParticipant.SlotPayload =
    slot == ._1 ? ._2 : ._1
  let partner = Components.Schemas.RelationshipParticipant(
    slot: partnerSlot,
    displayName: "여름",
    mine: false
  )
  let response = Components.Schemas.RelationshipScoresResponse(
    _self: selfParticipant,
    partner: partner,
    outgoing: .init(
      sourceParticipant: selfParticipant,
      targetParticipant: partner,
      currentScore: 50,
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    ),
    incoming: .init(
      sourceParticipant: partner,
      targetParticipant: selfParticipant,
      currentScore: 60,
      updatedAt: Date(timeIntervalSince1970: 1_700_000_001)
    )
  )
  return .ok(
    .init(
      headers: .init(cacheControl: "no-store"),
      body: .json(response)
    )
  )
}

private func makeUnauthorizedOutput() -> Operations.GetRelationshipScores.Output {
  let apiProblem = Components.Schemas.ApiProblem(
    title: "Authentication required",
    status: 401,
    detail: "Valid HTTP Basic participant credentials are required.",
    instance: "/api/v2/relationship-scores",
    errorCode: "AUTHENTICATION_REQUIRED"
  )
  let problem = Components.Schemas.AuthenticationRequiredProblem(
    value1: apiProblem,
    value2: .init()
  )
  return .unauthorized(
    .init(
      headers: .init(
        cacheControl: "no-store",
        wwwAuthenticate: .basicRealm_equals__quot_woorisai_quot_
      ),
      body: .applicationProblemJson(problem)
    )
  )
}

private func makeForbiddenOutput() -> Operations.GetRelationshipScores.Output {
  let apiProblem = Components.Schemas.ApiProblem(
    title: "Relationship access denied",
    status: 403,
    detail: "Access to this relationship resource is denied.",
    instance: "/api/v2/relationship-scores",
    errorCode: "RELATIONSHIP_FORBIDDEN"
  )
  let problem = Components.Schemas.RelationshipForbiddenProblem(
    value1: apiProblem,
    value2: .init()
  )
  return .forbidden(
    .init(
      headers: .init(cacheControl: "no-store"),
      body: .applicationProblemJson(problem)
    )
  )
}

private func makeServiceUnavailableOutput(
  errorCode: String
) -> Operations.GetRelationshipScores.Output {
  let apiProblem = Components.Schemas.ApiProblem(
    title: "Unavailable",
    status: 503,
    detail: "Temporarily unavailable.",
    instance: "/api/v2/relationship-scores",
    errorCode: errorCode
  )
  let payload:
    Components.Responses.RelationshipOrAuthenticationUnavailable.Body.ApplicationProblemJsonPayload
  if errorCode == "AUTHENTICATION_UNAVAILABLE" {
    payload = .AuthenticationUnavailableProblem(
      .init(value1: apiProblem, value2: .init())
    )
  } else {
    payload = .RelationshipUnavailableProblem(
      .init(value1: apiProblem, value2: .init())
    )
  }
  return .serviceUnavailable(
    .init(
      headers: .init(cacheControl: "no-store"),
      body: .applicationProblemJson(payload)
    )
  )
}
