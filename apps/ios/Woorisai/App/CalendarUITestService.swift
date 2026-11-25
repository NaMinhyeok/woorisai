#if DEBUG
  import Foundation
  import WoorisaiAPI

  // Deterministic UI-test-only empty response; production always uses the generated client.
  extension WoorisaiUITestService: CalendarServing {
    func listCalendarEvents(range: CalendarDateRange) async throws -> [CalendarEvent] { [] }
    func createCalendarEvent(_ draft: CalendarEventDraft) async throws -> CalendarEvent { throw WoorisaiAPIError.invalidRequest }
    func getCalendarEvent(id: Int64) async throws -> CalendarEvent { throw WoorisaiAPIError.notFound }
    func updateCalendarEvent(id: Int64, draft: CalendarEventDraft) async throws -> CalendarEvent { throw WoorisaiAPIError.notFound }
    func deleteCalendarEvent(id: Int64) async throws { throw WoorisaiAPIError.notFound }
  }
#endif
