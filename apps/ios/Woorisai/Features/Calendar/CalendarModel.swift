import Foundation
import Observation
import WoorisaiAPI

@MainActor @Observable
final class CalendarModel {
  private let service: any CalendarServing
  private let timeZone: TimeZone
  private var calendar: Calendar
  private var loadTask: Task<Void, Never>?
  private var mutationTask: Task<Void, Never>?
  private var generation = 0
  private var sessionEpoch = 0
  private(set) var selectedDay: Date
  private(set) var displayedMonth: Date
  private(set) var events: [CalendarEvent] = []
  private(set) var isLoading = false
  private(set) var isMutating = false
  private(set) var notice: String?
  private(set) var uncertainMutation = false
  private(set) var authenticationRequired = false
  private(set) var pendingDraft: CalendarEventDraft?
  var requiresNavigationProtection: Bool { isMutating || uncertainMutation }

  init(service: any CalendarServing, initialDate: Date = .now, timeZone: TimeZone = .current) {
    self.service = service; self.timeZone = timeZone
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    self.calendar = calendar
    selectedDay = calendar.startOfDay(for: initialDate)
    displayedMonth = calendar.dateInterval(of: .month, for: initialDate)!.start
  }

  var weekdaySymbols: [String] {
    let symbols = calendar.veryShortStandaloneWeekdaySymbols
    return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
  }

  var leadingEmptyDays: Int {
    (calendar.component(.weekday, from: displayedMonth) - calendar.firstWeekday + 7) % 7
  }

  var days: [Date] {
    guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
    return stride(from: 0, to: calendar.dateComponents([.day], from: interval.start, to: interval.end).day ?? 0, by: 1)
      .compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
  }

  func events(on day: Date) -> [CalendarEvent] {
    let start = calendar.startOfDay(for: day)
    guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
    return events.filter { $0.startAt < end && $0.endAt > start }
      .sorted { $0.startAt == $1.startAt ? $0.id < $1.id : $0.startAt < $1.startAt }
  }

  func select(_ day: Date) { selectedDay = calendar.startOfDay(for: day) }

  func changeMonth(by offset: Int) {
    guard let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
    displayedMonth = month
    selectedDay = month
    load()
  }

  func openEvent(id: Int64) {
    generation += 1
    let current = generation
    loadTask?.cancel()
    isLoading = true
    loadTask = Task {
      do {
        let event = try await service.getCalendarEvent(id: id)
        guard !Task.isCancelled, generation == current else { return }
        displayedMonth = calendar.dateInterval(of: .month, for: event.startAt)!.start
        selectedDay = calendar.startOfDay(for: event.startAt)
        load()
      } catch {
        guard !Task.isCancelled, generation == current else { return }
        if (error as? WoorisaiAPIError) == .credentialRejected { authenticationRequired = true }
        load()
        notice = (error as? WoorisaiAPIError) == .notFound
          ? "삭제되었거나 없는 일정이에요." : "일정을 확인하지 못했어요."
      }
    }
  }

  func load() {
    generation += 1
    let current = generation
    loadTask?.cancel()
    guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)!
    formatter.dateFormat = "yyyy-MM-dd"
    let lastMoment = interval.end.addingTimeInterval(-0.001)
    let range = CalendarDateRange(from: formatter.string(from: interval.start), to: formatter.string(from: lastMoment))
    isLoading = true; notice = nil
    loadTask = Task {
      do {
        let result = try await service.listCalendarEvents(range: range)
        guard !Task.isCancelled, generation == current else { return }
        events = result; isLoading = false
      } catch is CancellationError {
        if generation == current { isLoading = false }
      } catch {
        guard generation == current else { return }
        isLoading = false; notice = "일정을 불러오지 못했어요. 다시 시도해 주세요."
        if (error as? WoorisaiAPIError) == .credentialRejected { authenticationRequired = true }
      }
    }
  }

  func create(_ draft: CalendarEventDraft) { mutate(draft: draft) { try await self.service.createCalendarEvent(draft) } }
  func update(_ event: CalendarEvent, draft: CalendarEventDraft, as slot: ParticipantSlot) {
    guard event.canEdit(as: slot) else { notice = "수정 권한이 없어요."; return }
    mutate(draft: draft) { try await self.service.updateCalendarEvent(id: event.id, draft: draft) }
  }
  func delete(_ event: CalendarEvent, as slot: ParticipantSlot) {
    guard event.canEdit(as: slot) else { notice = "삭제 권한이 없어요."; return }
    guard !isMutating, !uncertainMutation else { return }
    isMutating = true
    let epoch = sessionEpoch
    mutationTask = Task {
      do {
        try await service.deleteCalendarEvent(id: event.id)
        guard !Task.isCancelled, epoch == sessionEpoch else { return }
        events.removeAll { $0.id == event.id }; isMutating = false
        load()
      } catch {
        guard !Task.isCancelled, epoch == sessionEpoch else { return }
        isMutating = false
        if (error as? WoorisaiAPIError) == .credentialRejected { authenticationRequired = true }
        uncertainMutation = (error as? WoorisaiAPIError) == .transport
        notice = uncertainMutation ? "삭제 결과를 확인할 수 없어요. 재전송하지 말고 일정을 새로 확인해 주세요." : "삭제하지 못했어요. 다시 확인해 주세요."
      }
    }
  }
  func abandonUncertainMutation() { uncertainMutation = false; pendingDraft = nil; notice = nil }
  func clear() {
    generation += 1; sessionEpoch += 1; loadTask?.cancel(); mutationTask?.cancel()
    events = []; notice = nil; pendingDraft = nil; uncertainMutation = false; authenticationRequired = false
    isLoading = false; isMutating = false
  }
  private func mutate(draft: CalendarEventDraft, action: @escaping @MainActor () async throws -> CalendarEvent) {
    guard !isMutating, !uncertainMutation else { return }
    isMutating = true; pendingDraft = draft; notice = nil
    let epoch = sessionEpoch
    mutationTask = Task {
      do {
        let event = try await action()
        guard !Task.isCancelled, epoch == sessionEpoch else { return }
        events.removeAll { $0.id == event.id }; events.append(event)
        isMutating = false; pendingDraft = nil
        load()
      } catch {
        guard !Task.isCancelled, epoch == sessionEpoch else { return }
        isMutating = false
        if (error as? WoorisaiAPIError) == .credentialRejected { authenticationRequired = true }
        uncertainMutation = (error as? WoorisaiAPIError) == .transport
        if !uncertainMutation { pendingDraft = nil }
        notice = uncertainMutation ? "저장 결과를 확인할 수 없어요. 자동으로 다시 보내지 않아요." : "저장하지 못했어요. 입력을 확인해 주세요."
      }
    }
  }
}
