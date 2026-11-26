#if DEBUG
  import Foundation
  import WoorisaiAPI

  // UI-test-only responses; production always uses the generated client.
  extension WoorisaiUITestService: CalendarServing {
    func listCalendarEvents(range: CalendarDateRange) async throws -> [CalendarEvent] {
      guard usesCalendarUXFixture else { return [] }
      return [Self.upcomingCalendarFixture] + addedCalendarFixtures
    }
    func createCalendarEvent(_ draft: CalendarEventDraft) async throws -> CalendarEvent {
      guard usesCalendarUXFixture else { throw WoorisaiAPIError.invalidRequest }
      let event = CalendarEvent(
        id: 701 + Int64(addedCalendarFixtures.count), title: draft.title,
        startAt: draft.startAt, endAt: draft.endAt, allDay: draft.allDay, note: draft.note,
        kind: draft.kind, author: Self.upcomingCalendarFixture.author,
        createdAt: .now, updatedAt: .now
      )
      addedCalendarFixtures.append(event)
      return event
    }
    func getCalendarEvent(id: Int64) async throws -> CalendarEvent {
      guard usesCalendarUXFixture, id == Self.upcomingCalendarFixture.id else {
        throw WoorisaiAPIError.notFound
      }
      return Self.upcomingCalendarFixture
    }
    func updateCalendarEvent(id: Int64, draft: CalendarEventDraft) async throws -> CalendarEvent { throw WoorisaiAPIError.notFound }
    func deleteCalendarEvent(id: Int64) async throws { throw WoorisaiAPIError.notFound }

    private static let upcomingCalendarFixture: CalendarEvent = {
      let now = Date.now
      let calendar = Calendar.current
      let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
      let start = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: tomorrow) ?? tomorrow
      return CalendarEvent(
        id: 700, title: "연남동 저녁 약속", startAt: start, endAt: start.addingTimeInterval(3600),
        allDay: false, note: nil, kind: .ours,
        author: DiaryParticipant(slot: .one, displayName: "봄"), createdAt: now, updatedAt: now
      )
    }()
  }
#endif
