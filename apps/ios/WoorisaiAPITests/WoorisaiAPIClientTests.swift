import Foundation
import OpenAPIRuntime
import Testing

@testable import WoorisaiAPI

struct WoorisaiAPIClientTests {
  @Test
  func mapsSuccessfulLoginOptionsInCanonicalSlotOrder() async throws {
    let output = try makeSuccessfulOutput(
      participantsJSON: """
        [
          {"participantSlot": 1, "displayName": "참가자A"},
          {"participantSlot": 2, "displayName": "참가자B"}
        ]
        """
    )
    let client = WoorisaiAPIClient(loginOptionsClient: LoginOptionsAPIStub(output: output))

    let options = try await client.loadLoginOptions()

    #expect(
      options == [
        LoginOption(slot: 1, displayName: "참가자A"),
        LoginOption(slot: 2, displayName: "참가자B"),
      ])
  }

  @Test
  func mapsDefinedServiceUnavailableProblem() async {
    do {
      let output = try makeServiceUnavailableOutput()
      let client = WoorisaiAPIClient(loginOptionsClient: LoginOptionsAPIStub(output: output))

      _ = try await client.loadLoginOptions()
      Issue.record("Expected loginOptionsUnavailable")
    } catch let error as WoorisaiAPIError {
      #expect(error == .loginOptionsUnavailable)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test(arguments: [
    """
    [
      {"participantSlot": 2, "displayName": "참가자B"},
      {"participantSlot": 1, "displayName": "참가자A"}
    ]
    """,
    """
    [
      {"participantSlot": 1, "displayName": "   "},
      {"participantSlot": 2, "displayName": "참가자B"}
    ]
    """,
  ])
  func rejectsMalformedCanonicalPair(participantsJSON: String) async throws {
    let output = try makeSuccessfulOutput(participantsJSON: participantsJSON)
    let client = WoorisaiAPIClient(loginOptionsClient: LoginOptionsAPIStub(output: output))

    do {
      _ = try await client.loadLoginOptions()
      Issue.record("Expected schemaDrift")
    } catch let error as WoorisaiAPIError {
      #expect(error == .schemaDrift)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func mapsUndocumentedStatusWithoutExposingGeneratedPayload() async {
    let output = Operations.ListLoginOptions.Output.undocumented(
      statusCode: 418,
      .init()
    )
    let client = WoorisaiAPIClient(loginOptionsClient: LoginOptionsAPIStub(output: output))

    do {
      _ = try await client.loadLoginOptions()
      Issue.record("Expected undocumentedResponse")
    } catch let error as WoorisaiAPIError {
      #expect(error == .undocumentedResponse(statusCode: 418))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func mapsTransportFailure() async {
    let client = WoorisaiAPIClient(
      loginOptionsClient: LoginOptionsAPIStub { input in
        throw ClientError(
          operationID: "listLoginOptions",
          operationInput: input,
          causeDescription: "synthetic transport failure",
          underlyingError: URLError(.timedOut)
        )
      }
    )

    do {
      _ = try await client.loadLoginOptions()
      Issue.record("Expected transport")
    } catch let error as WoorisaiAPIError {
      #expect(error == .transport)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func mapsResponseBodyStreamFailureToTransport() async {
    let client = WoorisaiAPIClient(
      loginOptionsClient: LoginOptionsAPIStub { input in
        throw ClientError(
          operationID: "listLoginOptions",
          operationInput: input,
          response: .init(status: .ok),
          causeDescription: "synthetic response body stream failure",
          underlyingError: URLError(.networkConnectionLost)
        )
      }
    )

    do {
      _ = try await client.loadLoginOptions()
      Issue.record("Expected transport")
    } catch let error as WoorisaiAPIError {
      #expect(error == .transport)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func mapsDecodingFailureToSchemaDrift() async {
    let client = WoorisaiAPIClient(
      loginOptionsClient: LoginOptionsAPIStub { input in
        throw ClientError(
          operationID: "listLoginOptions",
          operationInput: input,
          response: .init(status: .ok),
          causeDescription: "synthetic response decoding failure",
          underlyingError: DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "synthetic schema drift")
          )
        )
      }
    )

    do {
      _ = try await client.loadLoginOptions()
      Issue.record("Expected schemaDrift")
    } catch let error as WoorisaiAPIError {
      #expect(error == .schemaDrift)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func rethrowsCancellation() async {
    let client = WoorisaiAPIClient(
      loginOptionsClient: LoginOptionsAPIStub { input in
        throw ClientError(
          operationID: "listLoginOptions",
          operationInput: input,
          causeDescription: "synthetic cancellation",
          underlyingError: CancellationError()
        )
      }
    )

    do {
      _ = try await client.loadLoginOptions()
      Issue.record("Expected cancellation")
    } catch is CancellationError {
      // Expected: cancellation remains control flow rather than an API error.
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}

private struct LoginOptionsAPIStub: LoginOptionsAPIProtocol {
  private let handler:
    @Sendable (
      Operations.ListLoginOptions.Input
    ) async throws -> Operations.ListLoginOptions.Output

  init(output: Operations.ListLoginOptions.Output) {
    self.handler = { _ in output }
  }

  init(
    handler:
      @escaping @Sendable (
        Operations.ListLoginOptions.Input
      ) async throws -> Operations.ListLoginOptions.Output
  ) {
    self.handler = handler
  }

  func listLoginOptions(
    _ input: Operations.ListLoginOptions.Input
  ) async throws -> Operations.ListLoginOptions.Output {
    try await handler(input)
  }
}

private func makeSuccessfulOutput(
  participantsJSON: String
) throws -> Operations.ListLoginOptions.Output {
  let response = try JSONDecoder().decode(
    Components.Schemas.LoginOptionsResponse.self,
    from: Data("{\"participants\":\(participantsJSON)}".utf8)
  )
  return .ok(.init(headers: .init(cacheControl: "no-store"), body: .json(response)))
}

private func makeServiceUnavailableOutput() throws -> Operations.ListLoginOptions.Output {
  let problem = try JSONDecoder().decode(
    Components.Schemas.LoginOptionsUnavailableProblem.self,
    from: Data(
      """
      {
        "title": "Login options unavailable",
        "status": 503,
        "detail": "The participant login options are temporarily unavailable.",
        "instance": "/api/v2/auth/login-options",
        "errorCode": "LOGIN_OPTIONS_UNAVAILABLE"
      }
      """.utf8
    )
  )
  return .serviceUnavailable(
    .init(
      headers: .init(cacheControl: "no-store"),
      body: .applicationProblemJson(problem)
    )
  )
}
