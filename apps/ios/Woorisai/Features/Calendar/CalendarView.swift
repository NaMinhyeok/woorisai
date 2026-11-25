import SwiftUI
import WoorisaiAPI

// The form shows an inclusive final day; the API stores an exclusive end instant.
enum CalendarEditorDates {
  static func displayedEnd(_ storedEnd: Date, allDay: Bool, calendar: Calendar) -> Date {
    guard allDay else { return storedEnd }
    return calendar.date(byAdding: .day, value: -1, to: storedEnd) ?? storedEnd
  }

  static func exclusiveEnd(_ displayedEnd: Date, allDay: Bool, calendar: Calendar) -> Date {
    guard allDay else { return displayedEnd }
    let start = calendar.startOfDay(for: displayedEnd)
    return calendar.date(byAdding: .day, value: 1, to: start) ?? displayedEnd
  }
}

struct CalendarView: View {
  @State var model: CalendarModel
  let participant: AuthenticatedParticipant
  let onAuthenticationRequired: @MainActor () -> Void
  @State private var editor: CalendarEvent?
  @State private var creating = false
  @State private var deleting: CalendarEvent?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          HStack {
            Button { model.changeMonth(by: -1) } label: { Image(systemName: "chevron.left") }
              .accessibilityLabel("이전 달")
            Spacer()
            Text(model.displayedMonth, format: .dateTime.year().month(.wide))
              .font(.title2.bold())
              .accessibilityIdentifier("calendar.month")
            Spacer()
            Button { model.changeMonth(by: 1) } label: { Image(systemName: "chevron.right") }
              .accessibilityLabel("다음 달")
          }
          .padding(.horizontal)
          LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
              Text(model.weekdaySymbols[index])
                .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(0..<model.leadingEmptyDays, id: \.self) { _ in Color.clear.frame(height: 42) }
            ForEach(model.days, id: \.self) { day in
              Button {
                model.select(day)
              } label: {
                VStack(spacing: 4) {
                  Text(day, format: .dateTime.day())
                  Circle().fill(model.events(on: day).isEmpty ? .clear : Color.accentColor)
                    .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Calendar.current.isDate(day, inSameDayAs: model.selectedDay) ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
              }
              .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            }
          }
          if model.isLoading { ProgressView("일정을 불러오는 중이에요") }
          if let notice = model.notice {
            Text(notice).foregroundStyle(.red)
            Button("다시 불러오기") { model.load() }
          }
          if model.uncertainMutation {
            Button("재전송 없이 초안 정리") { model.abandonUncertainMutation() }
          }
          Text(model.selectedDay, format: .dateTime.month().day()).font(.headline)
          if model.events(on: model.selectedDay).isEmpty && !model.isLoading {
            ContentUnavailableView("이날은 일정이 없어요", systemImage: "calendar")
          }
          ForEach(model.events(on: model.selectedDay)) { event in
            VStack(alignment: .leading, spacing: 8) {
              Text(event.kind.label).font(.caption).foregroundStyle(.secondary)
              Text(event.title).font(.headline)
              Text(event.allDay ? "종일" : event.startAt.formatted(date: .omitted, time: .shortened))
              if let note = event.note, !note.isEmpty { Text(note) }
              Text(event.author.displayName).font(.caption)
              if event.canEdit(as: participant.slot) {
                HStack {
                  Button("수정") { editor = event }
                  Button("삭제", role: .destructive) { deleting = event }
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
          }
        }
        .padding()
      }
      .navigationTitle("일정")
      .toolbar {
        Button { creating = true } label: { Image(systemName: "plus") }
          .accessibilityLabel("일정 추가")
          .accessibilityIdentifier("calendar.create")
          .disabled(model.isMutating || model.uncertainMutation)
      }
      .sheet(isPresented: $creating) {
        CalendarEditor(model: model, event: nil, participant: participant)
      }
      .sheet(item: $editor) { event in
        CalendarEditor(model: model, event: event, participant: participant)
      }
      .confirmationDialog("일정을 삭제할까요?", isPresented: Binding(
        get: { deleting != nil }, set: { if !$0 { deleting = nil } }
      )) {
        Button("삭제", role: .destructive) {
          if let deleting { model.delete(deleting, as: participant.slot) }
          deleting = nil
        }
      }
      .task { if !model.isLoading && model.events.isEmpty { model.load() } }
      .onChange(of: model.notice) { _, _ in
        // Authentication failure is routed through the session owner, not hidden in a calendar alert.
        if model.authenticationRequired { onAuthenticationRequired() }
      }
    }
  }
}

private struct CalendarEditor: View {
  @Environment(\.dismiss) private var dismiss
  let model: CalendarModel
  let event: CalendarEvent?
  let participant: AuthenticatedParticipant
  @State private var title: String
  @State private var startAt: Date
  @State private var endAt: Date
  @State private var allDay: Bool
  @State private var note: String
  @State private var kind: CalendarEventKind
  @State private var error: String?
  @FocusState private var titleFocused: Bool

  init(model: CalendarModel, event: CalendarEvent?, participant: AuthenticatedParticipant) {
    self.model = model; self.event = event; self.participant = participant
    _title = State(initialValue: event?.title ?? "")
    let start = event?.startAt ?? model.selectedDay.addingTimeInterval(12 * 3600)
    _startAt = State(initialValue: start)
    _endAt = State(initialValue: event.map {
      CalendarEditorDates.displayedEnd($0.endAt, allDay: $0.allDay, calendar: .current)
    } ?? start.addingTimeInterval(3600))
    _allDay = State(initialValue: event?.allDay ?? false)
    _note = State(initialValue: event?.note ?? "")
    _kind = State(initialValue: event?.kind ?? .ours)
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("제목", text: $title)
          .focused($titleFocused)
          .accessibilityIdentifier("calendar.title")
        Picker("구분", selection: $kind) {
          ForEach(CalendarEventKind.allCases, id: \.self) { value in
            Text(value.label).tag(value)
          }
        }
        Toggle("종일", isOn: $allDay)
        DatePicker("시작", selection: $startAt, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
        DatePicker("종료", selection: $endAt, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
        TextField("메모", text: $note, axis: .vertical)
        if let error { Text(error).foregroundStyle(.red) }
        if model.uncertainMutation {
          Text("저장 결과를 알 수 없어요. 초안을 유지하고 있어요.")
          Button("재전송 없이 초안 정리") { model.abandonUncertainMutation() }
        }
      }
      .navigationTitle(event == nil ? "일정 추가" : "일정 수정")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("저장") { save() }
            .accessibilityIdentifier("calendar.save")
            .disabled(model.isMutating || model.uncertainMutation)
        }
      }
      .interactiveDismissDisabled(model.isMutating || model.uncertainMutation)
      .onChange(of: model.isMutating) { wasMutating, mutating in
        if wasMutating && !mutating && model.notice == nil { dismiss() }
        if wasMutating && !mutating { error = model.notice }
      }
    }
  }

  private func save() {
    do {
      let end = CalendarEditorDates.exclusiveEnd(endAt, allDay: allDay, calendar: .current)
      let start = allDay ? Calendar.current.startOfDay(for: startAt) : startAt
      let draft = try CalendarEventDraft(title: title, startAt: start, endAt: end, allDay: allDay, note: note.isEmpty ? nil : note, kind: kind)
      if let event { model.update(event, draft: draft, as: participant.slot) }
      else { model.create(draft) }
    } catch { self.error = "제목과 시작·종료 시각을 확인해 주세요." }
  }
}
