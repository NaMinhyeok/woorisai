import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

protocol CalendarAPIProtocol: Sendable {
  func listCalendarEvents(_ input: Operations.ListCalendarEvents.Input) async throws -> Operations.ListCalendarEvents.Output
  func createCalendarEvent(_ input: Operations.CreateCalendarEvent.Input) async throws -> Operations.CreateCalendarEvent.Output
  func getCalendarEvent(_ input: Operations.GetCalendarEvent.Input) async throws -> Operations.GetCalendarEvent.Output
  func updateCalendarEvent(_ input: Operations.UpdateCalendarEvent.Input) async throws -> Operations.UpdateCalendarEvent.Output
  func deleteCalendarEvent(_ input: Operations.DeleteCalendarEvent.Input) async throws -> Operations.DeleteCalendarEvent.Output
}
extension Client: CalendarAPIProtocol {}

/// The generator encodes a nullable Swift optional as absent even when OpenAPI requires the key.
/// Restrict the correction to calendar writes, preserving explicit notes and all other operations.
struct CalendarRequiredNullableNoteMiddleware: ClientMiddleware {
  func intercept(
    _ request: HTTPRequest,
    body: HTTPBody?,
    baseURL: URL,
    operationID: String,
    next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
  ) async throws -> (HTTPResponse, HTTPBody?) {
    guard operationID == "createCalendarEvent" || operationID == "updateCalendarEvent",
      let body else { return try await next(request, body, baseURL) }
    var bytes = Data()
    for try await chunk in body {
      bytes.append(contentsOf: chunk)
      guard bytes.count <= 16_384 else { throw WoorisaiAPIError.invalidRequest }
    }
    guard var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
      throw WoorisaiAPIError.schemaDrift
    }
    if object["note"] == nil { object["note"] = NSNull() }
    let corrected = try JSONSerialization.data(withJSONObject: object)
    var correctedRequest = request
    correctedRequest.headerFields[.contentLength] = String(corrected.count)
    return try await next(correctedRequest, HTTPBody(corrected), baseURL)
  }
}

public struct WoorisaiCalendarAPI: CalendarServing, Sendable {
  private let calendarClient: any CalendarAPIProtocol
  public init(baseURL: URL, credentialStore: InMemoryCredentialStore = .init()) throws {
    guard let origin = APIOrigin(url: baseURL) else { throw WoorisaiAPIError.untrustedOrigin }
    calendarClient = Client(serverURL: baseURL,
      configuration: .init(dateTranscoder: FlexibleISO8601DateTranscoder()),
      transport: WoorisaiAPITransportFactory.make(apiOrigin: origin),
      middlewares: [BasicAuthorizationMiddleware(apiOrigin: origin, credentialStore: credentialStore),
                    CalendarRequiredNullableNoteMiddleware()])
  }
  init(calendarClient: any CalendarAPIProtocol) { self.calendarClient = calendarClient }

  public func listCalendarEvents(range: CalendarDateRange) async throws -> [CalendarEvent] {
    guard Self.valid(range: range) else { throw WoorisaiAPIError.invalidRequest }
    return try await perform {
      switch try await calendarClient.listCalendarEvents(.init(query: .init(from: range.from, to: range.to))) {
      case .ok(let response):
        let events = try response.body.json.map(Self.map)
        guard zip(events, events.dropFirst()).allSatisfy({ $0.startAt < $1.startAt || ($0.startAt == $1.startAt && $0.id < $1.id) }) else { throw WoorisaiAPIError.schemaDrift }
        return events
      case .badRequest(let response): throw Self.problem(response)
      case .unauthorized(let response): throw Self.problem(response)
      case .serviceUnavailable(let response): throw Self.problem(response)
      case .undocumented(let code, _): throw WoorisaiAPIError.undocumentedResponse(statusCode: code)
      }
    }
  }
  public func createCalendarEvent(_ draft: CalendarEventDraft) async throws -> CalendarEvent {
    try await perform {
      switch try await calendarClient.createCalendarEvent(.init(body: .json(Self.request(draft)))) {
      case .created(let response): return try Self.map(response.body.json)
      case .badRequest(let response): throw Self.problem(response)
      case .unauthorized(let response): throw Self.problem(response)
      case .unsupportedMediaType(let response): throw Self.problem(response)
      case .serviceUnavailable(let response): throw Self.problem(response)
      case .undocumented(let code, _): throw WoorisaiAPIError.undocumentedResponse(statusCode: code)
      }
    }
  }
  public func getCalendarEvent(id: Int64) async throws -> CalendarEvent {
    try Self.valid(id: id)
    return try await perform {
      switch try await calendarClient.getCalendarEvent(.init(path: .init(eventId: id))) {
      case .ok(let response): return try Self.map(response.body.json)
      case .badRequest(let response): throw Self.problem(response)
      case .unauthorized(let response): throw Self.problem(response)
      case .notFound(let response): throw Self.problem(response)
      case .serviceUnavailable(let response): throw Self.problem(response)
      case .undocumented(let code, _): throw WoorisaiAPIError.undocumentedResponse(statusCode: code)
      }
    }
  }
  public func updateCalendarEvent(id: Int64, draft: CalendarEventDraft) async throws -> CalendarEvent {
    try Self.valid(id: id)
    return try await perform {
      switch try await calendarClient.updateCalendarEvent(.init(path: .init(eventId: id), body: .json(Self.request(draft)))) {
      case .ok(let response): return try Self.map(response.body.json)
      case .badRequest(let response): throw Self.problem(response)
      case .unauthorized(let response): throw Self.problem(response)
      case .forbidden(let response): throw Self.problem(response)
      case .notFound(let response): throw Self.problem(response)
      case .conflict(let response): throw Self.problem(response)
      case .unsupportedMediaType(let response): throw Self.problem(response)
      case .serviceUnavailable(let response): throw Self.problem(response)
      case .undocumented(let code, _): throw WoorisaiAPIError.undocumentedResponse(statusCode: code)
      }
    }
  }
  public func deleteCalendarEvent(id: Int64) async throws {
    try Self.valid(id: id)
    try await perform {
      switch try await calendarClient.deleteCalendarEvent(.init(path: .init(eventId: id))) {
      case .noContent: return
      case .badRequest(let response): throw Self.problem(response)
      case .unauthorized(let response): throw Self.problem(response)
      case .forbidden(let response): throw Self.problem(response)
      case .notFound(let response): throw Self.problem(response)
      case .conflict(let response): throw Self.problem(response)
      case .serviceUnavailable(let response): throw Self.problem(response)
      case .undocumented(let code, _): throw WoorisaiAPIError.undocumentedResponse(statusCode: code)
      }
    }
  }

  private static func request(_ draft: CalendarEventDraft) -> Components.Schemas.CalendarEventRequest {
    .init(title: draft.title, startAt: draft.startAt, endAt: draft.endAt, allDay: draft.allDay,
      note: draft.note, kind: draft.kind == .mine ? .mine : .ours)
  }
  private static func map(_ value: Components.Schemas.CalendarEvent) throws -> CalendarEvent {
    guard value.id > 0, value.startAt < value.endAt,
      !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      value.title.unicodeScalars.count <= 200, value.note.map({ $0.unicodeScalars.count <= 2_000 }) ?? true,
      value.createdAt <= value.updatedAt, !value.author.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      value.author.displayName.count <= 30, let slot = ParticipantSlot(rawValue: value.author.slot.rawValue)
    else { throw WoorisaiAPIError.schemaDrift }
    return CalendarEvent(id: value.id, title: value.title, startAt: value.startAt,
      endAt: value.endAt, allDay: value.allDay, note: value.note,
      kind: value.kind == .mine ? .mine : .ours,
      author: DiaryParticipant(slot: slot, displayName: value.author.displayName),
      createdAt: value.createdAt, updatedAt: value.updatedAt)
  }
  private static func valid(id: Int64) throws { if id <= 0 { throw WoorisaiAPIError.invalidRequest } }
  private static func valid(range: CalendarDateRange) -> Bool {
    let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(secondsFromGMT: 0)!; formatter.isLenient = false
    guard let start = formatter.date(from: range.from), let end = formatter.date(from: range.to),
      formatter.string(from: start) == range.from, formatter.string(from: end) == range.to else { return false }
    let days = Calendar(identifier: .gregorian).dateComponents([.day], from: start, to: end).day ?? -1
    return days >= 0 && days < 367
  }
  private func perform<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
    do { return try await operation() }
    catch is CancellationError { throw CancellationError() }
    catch let error as WoorisaiAPIError { throw error }
    catch let error as ClientError {
      if Task.isCancelled || error.underlyingError is CancellationError { throw CancellationError() }
      if let middleware = error.underlyingError as? APIAuthorizationMiddlewareError {
        switch middleware {
        case .credentialMissing: throw WoorisaiAPIError.credentialMissing
        case .unknownOperation: throw WoorisaiAPIError.schemaDrift
        case .untrustedOrigin: throw WoorisaiAPIError.untrustedOrigin
        }
      }
      if error.underlyingError is DecodingError || error.response != nil { throw WoorisaiAPIError.schemaDrift }
      throw WoorisaiAPIError.transport
    }
    catch is DecodingError { throw WoorisaiAPIError.schemaDrift }
    catch { if Task.isCancelled { throw CancellationError() }; throw WoorisaiAPIError.transport }
  }
  private static func problem(_ response: Components.Responses.InvalidCalendarRequest) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value): return .mapProblem(httpStatus: 400, problemStatus: value.value1.status, errorCode: value.value1.errorCode)
    }
  }
  private static func problem(_ response: Components.Responses.AuthenticationRequired) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value): return .mapProblem(httpStatus: 401, problemStatus: value.value1.status, errorCode: value.value1.errorCode)
    }
  }
  private static func problem(_ response: Components.Responses.CalendarForbidden) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value): return .mapProblem(httpStatus: 403, problemStatus: value.value1.status, errorCode: value.value1.errorCode)
    }
  }
  private static func problem(_ response: Components.Responses.CalendarNotFound) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value): return .mapProblem(httpStatus: 404, problemStatus: value.value1.status, errorCode: value.value1.errorCode)
    }
  }
  private static func problem(_ response: Components.Responses.CalendarConflict) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value): return .mapProblem(httpStatus: 409, problemStatus: value.value1.status, errorCode: value.value1.errorCode)
    }
  }
  private static func problem(_ response: Components.Responses.UnsupportedMediaType) -> WoorisaiAPIError {
    switch response.body {
    case .applicationProblemJson(let value): return .mapProblem(httpStatus: 415, problemStatus: value.value1.status, errorCode: value.value1.errorCode)
    }
  }
  private static func problem(_ response: Components.Responses.CalendarOrAuthenticationUnavailable) -> WoorisaiAPIError {
    let problem: Components.Schemas.ApiProblem
    switch response.body {
    case .applicationProblemJson(let payload):
      switch payload {
      case .AuthenticationUnavailableProblem(let value): problem = value.value1
      case .CalendarUnavailableProblem(let value): problem = value.value1
      }
    }
    return .mapProblem(httpStatus: 503, problemStatus: problem.status, errorCode: problem.errorCode)
  }
}

extension WoorisaiAPIClient: CalendarServing {
  public func listCalendarEvents(range: CalendarDateRange) async throws -> [CalendarEvent] { try await calendarAdapter().listCalendarEvents(range: range) }
  public func createCalendarEvent(_ draft: CalendarEventDraft) async throws -> CalendarEvent { try await calendarAdapter().createCalendarEvent(draft) }
  public func getCalendarEvent(id: Int64) async throws -> CalendarEvent { try await calendarAdapter().getCalendarEvent(id: id) }
  public func updateCalendarEvent(id: Int64, draft: CalendarEventDraft) async throws -> CalendarEvent { try await calendarAdapter().updateCalendarEvent(id: id, draft: draft) }
  public func deleteCalendarEvent(id: Int64) async throws { try await calendarAdapter().deleteCalendarEvent(id: id) }
  private func calendarAdapter() throws -> WoorisaiCalendarAPI {
    guard let client = client as? any CalendarAPIProtocol else { throw WoorisaiAPIError.schemaDrift }
    return WoorisaiCalendarAPI(calendarClient: client)
  }
}
