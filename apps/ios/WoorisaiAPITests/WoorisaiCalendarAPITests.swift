import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import WoorisaiAPI

struct WoorisaiCalendarAPITests {
  @Test
  func nullableNoteIsEncodedAsExplicitNullForRequiredWireField() async throws {
    let middleware = CalendarRequiredNullableNoteMiddleware()
    var request = HTTPRequest(method: .post, scheme: "https", authority: "api.example.test", path: "/api/v2/calendar/events")
    let body = HTTPBody("{\"title\":\"산책\"}")
    request.headerFields[.contentLength] = String("{\"title\":\"산책\"}".utf8.count)
    _ = try await middleware.intercept(request, body: body, baseURL: URL(string: "https://api.example.test")!, operationID: "createCalendarEvent") { outgoingRequest, outgoing, _ in
      var data = Data()
      for try await chunk in outgoing! { data.append(contentsOf: chunk) }
      #expect(outgoingRequest.headerFields[.contentLength] == String(data.count))
      let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
      #expect(json["note"] is NSNull)
      return (HTTPResponse(status: .ok), nil)
    }
  }
  @Test
  func forwardsCreateReadUpdateDeleteWithAuthorAndNote() async throws {
    let stub = CalendarAPIStub()
    let api = WoorisaiCalendarAPI(calendarClient: stub)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let draft = try CalendarEventDraft(title: "  산책  ", startAt: start, endAt: start.addingTimeInterval(3600), allDay: false, note: "함께", kind: .ours)
    let created = try await api.createCalendarEvent(draft)
    let fetched = try await api.getCalendarEvent(id: 9)
    let updated = try await api.updateCalendarEvent(id: 9, draft: draft)
    try await api.deleteCalendarEvent(id: 9)
    #expect(created.author.slot == .two)
    #expect(fetched.id == 9 && updated.id == 9)
    #expect(await stub.createRequest?.title == "산책")
    #expect(await stub.createRequest?.note == "함께")
    #expect(await stub.createRequest?.kind == .ours)
    #expect(await stub.updatedID == 9)
    #expect(await stub.deletedID == 9)
  }

  @Test
  func mapsGeneratedEventAndForwardsInclusiveRange() async throws {
    let stub = CalendarAPIStub()
    let api = WoorisaiCalendarAPI(calendarClient: stub)
    let events = try await api.listCalendarEvents(range: .init(from: "2026-11-01", to: "2026-11-30"))
    #expect(await stub.range?.from == "2026-11-01")
    #expect(await stub.range?.to == "2026-11-30")
    #expect(events.count == 1)
    #expect(events.first?.author.slot == .two)
    #expect(events.first?.kind == .ours)
  }
  @Test
  func calendarOperationsRequireBasicAuthorization() throws {
    for operation in ["listCalendarEvents", "createCalendarEvent", "getCalendarEvent", "updateCalendarEvent", "deleteCalendarEvent"] {
      #expect(try APIOperationAuthorizationPolicy.requirement(for: operation) == .credential)
    }
  }

  @Test
  func draftRejectsBlankTitlesAndNonIncreasingTime() throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try CalendarEventDraft(title: " \n", startAt: start, endAt: start.addingTimeInterval(60), allDay: false, note: nil, kind: .ours)
    }
    #expect(throws: WoorisaiAPIError.invalidRequest) {
      _ = try CalendarEventDraft(title: "Dinner", startAt: start, endAt: start, allDay: false, note: nil, kind: .mine)
    }
  }
}
