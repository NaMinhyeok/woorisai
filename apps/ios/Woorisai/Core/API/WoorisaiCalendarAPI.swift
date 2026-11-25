import Foundation

public enum CalendarEventKind: String, Equatable, Sendable, CaseIterable {
  case mine = "MINE"
  case ours = "OURS"

  public var label: String { self == .mine ? "내 일정" : "우리 일정" }
}

public struct CalendarDateRange: Equatable, Sendable {
  public let from: String
  public let to: String
  public init(from: String, to: String) { self.from = from; self.to = to }
}

public struct CalendarEvent: Equatable, Sendable, Identifiable {
  public let id: Int64
  public let title: String
  public let startAt: Date
  public let endAt: Date
  public let allDay: Bool
  public let note: String?
  public let kind: CalendarEventKind
  public let author: DiaryParticipant
  public let createdAt: Date
  public let updatedAt: Date

  public init(id: Int64, title: String, startAt: Date, endAt: Date, allDay: Bool, note: String?, kind: CalendarEventKind, author: DiaryParticipant, createdAt: Date, updatedAt: Date) {
    self.id = id; self.title = title; self.startAt = startAt; self.endAt = endAt
    self.allDay = allDay; self.note = note; self.kind = kind; self.author = author
    self.createdAt = createdAt; self.updatedAt = updatedAt
  }

  public func canEdit(as slot: ParticipantSlot) -> Bool { kind == .ours || author.slot == slot }
}

public struct CalendarEventDraft: Equatable, Sendable {
  public let title: String
  public let startAt: Date
  public let endAt: Date
  public let allDay: Bool
  public let note: String?
  public let kind: CalendarEventKind

  public init(title: String, startAt: Date, endAt: Date, allDay: Bool, note: String?, kind: CalendarEventKind) throws {
    let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, normalized.unicodeScalars.count <= 200, endAt > startAt,
      note.map({ $0.unicodeScalars.count <= 2_000 }) ?? true else { throw WoorisaiAPIError.invalidRequest }
    self.title = normalized; self.startAt = startAt; self.endAt = endAt
    self.allDay = allDay; self.note = note; self.kind = kind
  }
}

public protocol CalendarServing: Sendable {
  func listCalendarEvents(range: CalendarDateRange) async throws -> [CalendarEvent]
  func createCalendarEvent(_ draft: CalendarEventDraft) async throws -> CalendarEvent
  func getCalendarEvent(id: Int64) async throws -> CalendarEvent
  func updateCalendarEvent(id: Int64, draft: CalendarEventDraft) async throws -> CalendarEvent
  func deleteCalendarEvent(id: Int64) async throws
}
