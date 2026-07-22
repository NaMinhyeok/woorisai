import Foundation
import OpenAPIRuntime

/// An app-owned Firebase installation identifier. Generated OpenAPI types stay inside this
/// adapter, and malformed provider values never reach the authenticated backend operation.
public struct NotificationInstallationID: Equatable, Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) throws {
    let bytes = Array(rawValue.utf8)
    guard bytes.count == 22,
      bytes.allSatisfy({ byte in
        (0x30...0x39).contains(byte)
          || (0x41...0x5A).contains(byte)
          || (0x61...0x7A).contains(byte)
          || byte == 0x2D
          || byte == 0x5F
      })
    else {
      throw WoorisaiAPIError.invalidRequest
    }

    self.rawValue = rawValue
  }
}

public protocol NotificationFIDServing: Sendable {
  func registerNotificationFID(_ fid: NotificationInstallationID) async throws
  func unregisterNotificationFID(_ fid: NotificationInstallationID) async throws
}

protocol NotificationFIDAPIProtocol: Sendable {
  func registerNotificationFid(
    _ input: Operations.RegisterNotificationFid.Input
  ) async throws -> Operations.RegisterNotificationFid.Output

  func unregisterNotificationFid(
    _ input: Operations.UnregisterNotificationFid.Input
  ) async throws -> Operations.UnregisterNotificationFid.Output
}

extension Client: NotificationFIDAPIProtocol {}

struct NotificationFIDAPIAdapter: NotificationFIDServing, Sendable {
  let client: any NotificationFIDAPIProtocol

  func registerNotificationFID(_ fid: NotificationInstallationID) async throws {
    try await performRequest { client in
      let output = try await client.registerNotificationFid(
        .init(body: .json(.init(fid: fid.rawValue)))
      )
      switch output {
      case .noContent:
        return
      case .badRequest(let response):
        throw Self.mapProblem(response)
      case .unauthorized(let response):
        throw Self.mapProblem(response)
      case .unsupportedMediaType(let response):
        throw Self.mapProblem(response)
      case .serviceUnavailable(let response):
        throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  func unregisterNotificationFID(_ fid: NotificationInstallationID) async throws {
    try await performRequest { client in
      let output = try await client.unregisterNotificationFid(
        .init(body: .json(.init(fid: fid.rawValue)))
      )
      switch output {
      case .noContent:
        return
      case .badRequest(let response):
        throw Self.mapProblem(response)
      case .unauthorized(let response):
        throw Self.mapProblem(response)
      case .unsupportedMediaType(let response):
        throw Self.mapProblem(response)
      case .serviceUnavailable(let response):
        throw Self.mapProblem(response)
      case .undocumented(let statusCode, _):
        throw WoorisaiAPIError.undocumentedResponse(statusCode: statusCode)
      }
    }
  }

  private func performRequest<T: Sendable>(
    _ operation: (any NotificationFIDAPIProtocol) async throws -> T
  ) async throws -> T {
    do {
      return try await operation(client)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as WoorisaiAPIError {
      throw error
    } catch let error as ClientError {
      if Task.isCancelled || error.underlyingError is CancellationError {
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
        throw CancellationError()
      }
      if error is URLError {
        throw WoorisaiAPIError.transport
      }
      throw WoorisaiAPIError.transport
    }
  }

  private static func mapProblem(
    _ response: Components.Responses.InvalidNotificationFid
  ) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value):
      return .mapProblem(
        httpStatus: 400,
        problemStatus: value.value1.status,
        errorCode: value.value1.errorCode
      )
    }
  }

  private static func mapProblem(
    _ response: Components.Responses.AuthenticationRequired
  ) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value):
      return .mapProblem(
        httpStatus: 401,
        problemStatus: value.value1.status,
        errorCode: value.value1.errorCode
      )
    }
  }

  private static func mapProblem(
    _ response: Components.Responses.UnsupportedMediaType
  ) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value):
      return .mapProblem(
        httpStatus: 415,
        problemStatus: value.value1.status,
        errorCode: value.value1.errorCode
      )
    }
  }

  private static func mapProblem(
    _ response: Components.Responses.NotificationFidOrAuthenticationUnavailable
  ) -> WoorisaiAPIError {
    let problem: Components.Schemas.NotificationApiProblem
    switch response.body {
    case .applicationProblemJson(let payload):
      switch payload {
      case .AuthenticationUnavailableProblem(let value):
        return .mapProblem(
          httpStatus: 503,
          problemStatus: value.value1.status,
          errorCode: value.value1.errorCode
        )
      case .NotificationFidUnavailableProblem(let value):
        problem = value.value1
      }
    }
    return .mapProblem(
      httpStatus: 503,
      problemStatus: problem.status,
      errorCode: problem.errorCode
    )
  }
}

extension WoorisaiAPIClient: NotificationFIDServing {
  public func registerNotificationFID(_ fid: NotificationInstallationID) async throws {
    guard let client = client as? any NotificationFIDAPIProtocol else {
      throw WoorisaiAPIError.schemaDrift
    }
    try await NotificationFIDAPIAdapter(client: client).registerNotificationFID(fid)
  }

  public func unregisterNotificationFID(_ fid: NotificationInstallationID) async throws {
    guard let client = client as? any NotificationFIDAPIProtocol else {
      throw WoorisaiAPIError.schemaDrift
    }
    try await NotificationFIDAPIAdapter(client: client).unregisterNotificationFID(fid)
  }
}
