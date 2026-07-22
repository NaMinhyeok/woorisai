import Foundation
import OpenAPIRuntime

protocol CredentialValidationAPIProtocol: Sendable {
  func getRelationshipScores(
    _ input: Operations.GetRelationshipScores.Input
  ) async throws -> Operations.GetRelationshipScores.Output
}

extension Client: CredentialValidationAPIProtocol {}

public struct AuthenticatedParticipant: Equatable, Sendable {
  public let slot: ParticipantSlot
  public let displayName: String

  public init(slot: ParticipantSlot, displayName: String) {
    self.slot = slot
    self.displayName = displayName
  }
}

public protocol CredentialValidating: Sendable {
  /// Stores the supplied credential in process memory and verifies it with one protected read.
  /// A rejected credential is removed before this method returns.
  func validateCredential(
    _ credential: ParticipantCredential
  ) async throws -> AuthenticatedParticipant
}

extension WoorisaiAPIClient: CredentialValidating {
  init(
    credentialValidationClient: any CredentialValidationAPIProtocol,
    credentialStore: InMemoryCredentialStore = InMemoryCredentialStore()
  ) {
    client = nil
    loginOptionsClient = nil
    self.credentialValidationClient = credentialValidationClient
    relationshipClient = nil
    self.credentialStore = credentialStore
  }

  public func validateCredential(
    _ credential: ParticipantCredential
  ) async throws -> AuthenticatedParticipant {
    guard let credentialValidationClient else {
      throw WoorisaiAPIError.schemaDrift
    }

    let credentialLease = await credentialStore.replaceAndLease(with: credential)

    do {
      try Task.checkCancellation()
      let output = try await credentialValidationClient.getRelationshipScores(.init())
      try Task.checkCancellation()
      switch output {
      case .ok(let response):
        return try Self.makeAuthenticatedParticipant(
          expectedSlot: credential.slot,
          from: response.body
        )
      case .unauthorized(let response):
        let problem: Components.Schemas.AuthenticationRequiredProblem
        switch response.body {
        case .applicationProblemJson(let value):
          problem = value
        }
        let error = WoorisaiAPIError.mapProblem(
          httpStatus: 401,
          problemStatus: problem.value1.status,
          errorCode: problem.value1.errorCode
        )
        if error == .credentialRejected {
          await credentialStore.clear(ifCurrent: credentialLease)
        }
        throw error
      case .forbidden(let response):
        let problem: Components.Schemas.RelationshipForbiddenProblem
        switch response.body {
        case .applicationProblemJson(let value):
          problem = value
        }
        throw WoorisaiAPIError.mapProblem(
          httpStatus: 403,
          problemStatus: problem.value1.status,
          errorCode: problem.value1.errorCode
        )
      case .serviceUnavailable(let response):
        let problem: Components.Schemas.ApiProblem
        switch response.body {
        case .applicationProblemJson(let payload):
          switch payload {
          case .AuthenticationUnavailableProblem(let value):
            problem = value.value1
          case .RelationshipUnavailableProblem(let value):
            problem = value.value1
          }
        }
        throw WoorisaiAPIError.mapProblem(
          httpStatus: 503,
          problemStatus: problem.status,
          errorCode: problem.errorCode
        )
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    } catch is CancellationError {
      await credentialStore.clear(ifCurrent: credentialLease)
      throw CancellationError()
    } catch let error as WoorisaiAPIError {
      throw error
    } catch let error as ClientError {
      if Task.isCancelled || error.underlyingError is CancellationError {
        await credentialStore.clear(ifCurrent: credentialLease)
        throw CancellationError()
      }
      if error.underlyingError is URLError {
        throw WoorisaiAPIError.transport
      }
      if let middlewareError = error.underlyingError as? APIAuthorizationMiddlewareError {
        switch middlewareError {
        case .credentialMissing:
          throw WoorisaiAPIError.credentialMissing
        case .unknownOperation:
          throw WoorisaiAPIError.schemaDrift
        case .untrustedOrigin:
          throw WoorisaiAPIError.untrustedOrigin
        }
      }
      if error.underlyingError is DecodingError || error.response != nil {
        throw WoorisaiAPIError.schemaDrift
      }
      throw WoorisaiAPIError.transport
    } catch is DecodingError {
      throw WoorisaiAPIError.schemaDrift
    } catch {
      if Task.isCancelled {
        await credentialStore.clear(ifCurrent: credentialLease)
        throw CancellationError()
      }
      throw WoorisaiAPIError.transport
    }
  }

  private static func makeAuthenticatedParticipant(
    expectedSlot: ParticipantSlot,
    from body: Operations.GetRelationshipScores.Output.Ok.Body
  ) throws -> AuthenticatedParticipant {
    let response: Components.Schemas.RelationshipScoresResponse
    switch body {
    case .json(let value):
      response = value
    }

    guard response._self.mine,
      response._self.slot.rawValue == expectedSlot.rawValue,
      !response._self.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw WoorisaiAPIError.schemaDrift
    }

    return AuthenticatedParticipant(
      slot: expectedSlot,
      displayName: response._self.displayName
    )
  }
}
