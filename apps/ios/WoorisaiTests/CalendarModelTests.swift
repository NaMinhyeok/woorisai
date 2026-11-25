import Foundation
import Testing
import WoorisaiAPI

@testable import Woorisai

@MainActor
struct CalendarModelTests {
  @Test
  func clearedSessionCannotPublishLateMutationResponse() async throws {
    let service = CalendarServiceStub()
    await service.setCreateDelay(true)
    let model = CalendarModel(service: service, initialDate: date("2026-11-25T12:00:00Z"), timeZone: .gmt)
    let draft = try CalendarEventDraft(title: "저녁", startAt: date("2026-11-25T12:00:00Z"), endAt: date("2026-11-25T13:00:00Z"), allDay: false, note: nil, kind: .ours)
    model.create(draft)
    #expect(model.requiresNavigationProtection)
    await eventually { await service.createCount == 1 }
    model.clear()
    await service.releaseCreate()
    await eventually { await service.createCompleted }
    try? await Task.sleep(for: .milliseconds(20))
    #expect(model.events.isEmpty)
    #expect(await service.lastRange == nil)
    #expect(!model.isMutating)
  }

  @Test
  func monthGridStartsOnCorrectWeekday() {
    let model = CalendarModel(service: CalendarServiceStub(), initialDate: date("2026-11-25T12:00:00Z"), timeZone: .gmt)
    #expect(model.leadingEmptyDays == 0) // November 1, 2026 is Sunday
    model.changeMonth(by: 1)
    #expect(model.leadingEmptyDays == 2) // December 1 is Tuesday
  }

  @Test
  func localMonthRequestsUTCOverlappingBoundaryDays() async {
    let service = CalendarServiceStub()
    let zone = TimeZone(secondsFromGMT: 9 * 3600)!
    let model = CalendarModel(service: service, initialDate: date("2026-11-25T12:00:00Z"), timeZone: zone)
    model.load()
    await eventually { await service.lastRange != nil }
    #expect(await service.lastRange == CalendarDateRange(from: "2026-10-31", to: "2026-11-30"))
  }

  @Test
  func monthRangeAndOvernightEventsAppearOnBothDays() async throws {
    let service = CalendarServiceStub()
    let model = CalendarModel(service: service, initialDate: date("2026-11-25T12:00:00Z"), timeZone: .gmt)
    await service.setEvents([event(start: "2026-11-30T23:00:00Z", end: "2026-12-01T01:00:00Z")])
    model.load()
    await eventually { model.events.count == 1 }
    #expect(await service.lastRange == CalendarDateRange(from: "2026-11-01", to: "2026-11-30"))
    #expect(model.events(on: date("2026-11-30T12:00:00Z")).count == 1)
    model.select(date("2026-12-01T12:00:00Z"))
    #expect(model.events(on: model.selectedDay).count == 1)
  }

  @Test
  func allDayEditorShowsInclusiveEndAndPreservesExclusiveStoredEnd() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let start = date("2026-11-24T15:00:00Z")
    let exclusiveEnd = date("2026-11-26T15:00:00Z")
    let displayedEnd = CalendarEditorDates.displayedEnd(exclusiveEnd, allDay: true, calendar: calendar)
    #expect(calendar.isDate(displayedEnd, inSameDayAs: date("2026-11-25T15:00:00Z")))
    #expect(CalendarEditorDates.exclusiveEnd(displayedEnd, allDay: true, calendar: calendar) == exclusiveEnd)
    #expect(CalendarEditorDates.displayedEnd(exclusiveEnd, allDay: false, calendar: calendar) == exclusiveEnd)
  }

  @Test
  func onlyAuthorCanEditMineWhileEitherCanEditOurs() {
    let mine = event(kind: .mine, authorSlot: .one)
    let ours = event(kind: .ours, authorSlot: .one)
    #expect(mine.canEdit(as: .one))
    #expect(!mine.canEdit(as: .two))
    #expect(ours.canEdit(as: .two))
  }

  @Test
  func uncertainWriteKeepsDraftWithoutAutomaticResend() async throws {
    let service = CalendarServiceStub()
    await service.setFailure(.transport)
    let model = CalendarModel(service: service, initialDate: date("2026-11-25T12:00:00Z"), timeZone: .gmt)
    let draft = try CalendarEventDraft(title: "저녁", startAt: date("2026-11-25T12:00:00Z"), endAt: date("2026-11-25T13:00:00Z"), allDay: false, note: nil, kind: .ours)
    model.create(draft)
    await eventually { model.uncertainMutation }
    #expect(await service.createCount == 1)
    #expect(model.pendingDraft == draft)
    #expect(model.requiresNavigationProtection)
    model.abandonUncertainMutation()
    #expect(!model.uncertainMutation)
    #expect(!model.requiresNavigationProtection)
    #expect(await service.createCount == 1)
  }

  private func eventually(_ condition: @escaping () async -> Bool) async {
    for _ in 0..<100 {
      if await condition() { return }
      try? await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Timed out waiting for calendar state")
  }
}

private func date(_ value: String) -> Date {
  ISO8601DateFormatter().date(from: value)!
}

private func event(start: String = "2026-11-25T12:00:00Z", end: String = "2026-11-25T13:00:00Z", kind: CalendarEventKind = .mine, authorSlot: ParticipantSlot = .one) -> CalendarEvent {
  CalendarEvent(id: 1, title: "저녁", startAt: date(start), endAt: date(end), allDay: false, note: nil, kind: kind, author: DiaryParticipant(slot: authorSlot, displayName: "봄"), createdAt: date(start), updatedAt: date(start))
}

private actor CalendarServiceStub: CalendarServing {
  var events: [CalendarEvent] = []
  var lastRange: CalendarDateRange?
  var createCount = 0
  var failure: WoorisaiAPIError?
  var createCompleted = false
  private var createDelay = false
  private var continuation: CheckedContinuation<Void, Never>?
  func setCreateDelay(_ value: Bool) { createDelay = value }
  func releaseCreate() { continuation?.resume(); continuation = nil }
  func setEvents(_ value: [CalendarEvent]) { events = value }
  func setFailure(_ value: WoorisaiAPIError) { failure = value }
  func listCalendarEvents(range: CalendarDateRange) async throws -> [CalendarEvent] { lastRange = range; return events }
  func createCalendarEvent(_ draft: CalendarEventDraft) async throws -> CalendarEvent {
    createCount += 1
    if createDelay { await withCheckedContinuation { continuation = $0 } }
    createCompleted = true
    if let failure { throw failure }
    return event()
  }
  func getCalendarEvent(id: Int64) async throws -> CalendarEvent { return event() }
  func updateCalendarEvent(id: Int64, draft: CalendarEventDraft) async throws -> CalendarEvent { return event() }
  func deleteCalendarEvent(id: Int64) async throws {}
}
