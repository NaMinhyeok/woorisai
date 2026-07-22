import Foundation
import OpenAPIRuntime
import Testing

@testable import WoorisaiAPI

struct WoorisaiNotificationAPITests {
  private let fid = try! NotificationInstallationID("c123456789012345678901")

  @Test
  func acceptsOnlyExactBase64URLInstallationIdentifiers() throws {
    #expect(
      try NotificationInstallationID("A_b-234567890123456789") == fidWith("A_b-234567890123456789"))

    #expect(throws: WoorisaiAPIError.invalidRequest) {
      try NotificationInstallationID("c12345678901234567890")
    }
    #expect(throws: WoorisaiAPIError.invalidRequest) {
      try NotificationInstallationID("c1234567890123456789012")
    }
    #expect(throws: WoorisaiAPIError.invalidRequest) {
      try NotificationInstallationID("c12345678901234567890=")
    }
    #expect(throws: WoorisaiAPIError.invalidRequest) {
      try NotificationInstallationID("가12345678901234567890")
    }
  }

  @Test
  func registerAndUnregisterSendTheValidatedFIDExactlyOnce() async throws {
    let recorder = NotificationInputRecorder()
    let stub = NotificationFIDAPIStub(
      register: { input in
        await recorder.record(register: input)
        return .noContent(.init(headers: .init(cacheControl: "no-store")))
      },
      unregister: { input in
        await recorder.record(unregister: input)
        return .noContent(.init(headers: .init(cacheControl: "no-store")))
      }
    )
    let adapter = NotificationFIDAPIAdapter(client: stub)

    try await adapter.registerNotificationFID(fid)
    try await adapter.unregisterNotificationFID(fid)

    let registerInput = try #require(await recorder.registerInput)
    let unregisterInput = try #require(await recorder.unregisterInput)
    guard case .json(let registerBody) = registerInput.body,
      case .json(let unregisterBody) = unregisterInput.body
    else {
      Issue.record("Expected JSON FID request bodies")
      return
    }
    #expect(registerBody.fid == fid.rawValue)
    #expect(unregisterBody.fid == fid.rawValue)
    #expect(await recorder.registerCount == 1)
    #expect(await recorder.unregisterCount == 1)
  }

  @Test
  func mapsContractProblemsAndDoesNotRetry() async throws {
    let counter = NotificationInvocationCounter()
    let invalid = Components.Schemas.InvalidNotificationFidProblem(
      value1: .init(
        title: "Invalid notification FID request",
        status: 400,
        detail: "Invalid request.",
        errorCode: "INVALID_NOTIFICATION_FID"
      ),
      value2: .init()
    )
    let stub = NotificationFIDAPIStub(register: { _ in
      await counter.increment()
      return .badRequest(
        .init(
          headers: .init(cacheControl: "no-store"),
          body: .applicationProblemJson(invalid)
        )
      )
    })
    let adapter = NotificationFIDAPIAdapter(client: stub)

    await #expect(throws: WoorisaiAPIError.invalidRequest) {
      try await adapter.registerNotificationFID(fid)
    }
    #expect(await counter.value == 1)
  }

  @Test
  func mapsUnknownResponsesAndTransportFailuresWithoutRetry() async throws {
    let undocumented = NotificationFIDAPIAdapter(
      client: NotificationFIDAPIStub(register: { _ in
        .undocumented(statusCode: 418, .init(headerFields: [:], body: nil))
      })
    )
    await #expect(throws: WoorisaiAPIError.undocumentedResponse(statusCode: 418)) {
      try await undocumented.registerNotificationFID(fid)
    }

    let counter = NotificationInvocationCounter()
    let transport = NotificationFIDAPIAdapter(
      client: NotificationFIDAPIStub(unregister: { _ in
        await counter.increment()
        throw URLError(.networkConnectionLost)
      })
    )
    await #expect(throws: WoorisaiAPIError.transport) {
      try await transport.unregisterNotificationFID(fid)
    }
    #expect(await counter.value == 1)
  }

  private func fidWith(_ rawValue: String) throws -> NotificationInstallationID {
    try NotificationInstallationID(rawValue)
  }
}

private struct NotificationFIDAPIStub: NotificationFIDAPIProtocol {
  typealias RegisterHandler =
    @Sendable (Operations.RegisterNotificationFid.Input) async throws ->
    Operations.RegisterNotificationFid.Output
  typealias UnregisterHandler =
    @Sendable (
      Operations.UnregisterNotificationFid.Input
    ) async throws -> Operations.UnregisterNotificationFid.Output

  private let register: RegisterHandler?
  private let unregister: UnregisterHandler?

  init(
    register: RegisterHandler? = nil,
    unregister: UnregisterHandler? = nil
  ) {
    self.register = register
    self.unregister = unregister
  }

  func registerNotificationFid(
    _ input: Operations.RegisterNotificationFid.Input
  ) async throws -> Operations.RegisterNotificationFid.Output {
    guard let register else { throw NotificationAPITestFailure.unexpectedOperation }
    return try await register(input)
  }

  func unregisterNotificationFid(
    _ input: Operations.UnregisterNotificationFid.Input
  ) async throws -> Operations.UnregisterNotificationFid.Output {
    guard let unregister else { throw NotificationAPITestFailure.unexpectedOperation }
    return try await unregister(input)
  }
}

private actor NotificationInputRecorder {
  private(set) var registerInput: Operations.RegisterNotificationFid.Input?
  private(set) var unregisterInput: Operations.UnregisterNotificationFid.Input?
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0

  func record(register input: Operations.RegisterNotificationFid.Input) {
    registerInput = input
    registerCount += 1
  }

  func record(unregister input: Operations.UnregisterNotificationFid.Input) {
    unregisterInput = input
    unregisterCount += 1
  }
}

private actor NotificationInvocationCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}

private enum NotificationAPITestFailure: Error {
  case unexpectedOperation
}
