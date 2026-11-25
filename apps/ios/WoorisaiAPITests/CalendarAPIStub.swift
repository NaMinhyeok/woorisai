import Foundation
import Testing

@testable import WoorisaiAPI

actor CalendarAPIStub: CalendarAPIProtocol {
  var range: Operations.ListCalendarEvents.Input.Query?
  var createRequest: Components.Schemas.CalendarEventRequest?
  var updatedID: Int64?
  var deletedID: Int64?
  private let fixture = Components.Schemas.CalendarEvent(id: 9, title: "산책", startAt: Date(timeIntervalSince1970: 1_700_000_000), endAt: Date(timeIntervalSince1970: 1_700_003_600), allDay: false, note: nil, kind: .ours, author: .init(slot: ._2, displayName: "새미"), createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
  func listCalendarEvents(_ input: Operations.ListCalendarEvents.Input) async throws -> Operations.ListCalendarEvents.Output {
    range = input.query
    return .ok(.init(headers: .init(cacheControl: "no-store"), body: .json([fixture])))
  }
  func createCalendarEvent(_ input: Operations.CreateCalendarEvent.Input) async throws -> Operations.CreateCalendarEvent.Output {
    if case .json(let request) = input.body { createRequest = request }
    return .created(.init(headers: .init(cacheControl: "no-store"), body: .json(fixture)))
  }
  func getCalendarEvent(_ input: Operations.GetCalendarEvent.Input) async throws -> Operations.GetCalendarEvent.Output {
    return .ok(.init(headers: .init(cacheControl: "no-store"), body: .json(fixture)))
  }
  func updateCalendarEvent(_ input: Operations.UpdateCalendarEvent.Input) async throws -> Operations.UpdateCalendarEvent.Output {
    updatedID = input.path.eventId
    return .ok(.init(headers: .init(cacheControl: "no-store"), body: .json(fixture)))
  }
  func deleteCalendarEvent(_ input: Operations.DeleteCalendarEvent.Input) async throws -> Operations.DeleteCalendarEvent.Output {
    deletedID = input.path.eventId
    return .noContent(.init(headers: .init(cacheControl: "no-store")))
  }
}
