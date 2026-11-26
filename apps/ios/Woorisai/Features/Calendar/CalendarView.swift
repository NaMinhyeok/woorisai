import SwiftUI
import WoorisaiAPI

// The form shows an inclusive final day; the API stores an exclusive end instant.
enum CalendarEditorDates {
  static func endAfterStartChange(_ start: Date, previousEnd: Date, allDay: Bool, calendar: Calendar) -> Date {
    guard !allDay else { return previousEnd }
    return calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
  }

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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State var model: CalendarModel
  let participant: AuthenticatedParticipant
  let onAuthenticationRequired: @MainActor () -> Void
  @State private var editor: CalendarEvent?
  @State private var creating = false
  @State private var deleting: CalendarEvent?
  @State private var monthDirection: CGFloat = 1

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: WoorisaiSpacing.regular) {
          monthCard
          if model.isLoading { ProgressView("일정을 불러오는 중이에요") }
          if let notice = model.notice {
            Text(notice).foregroundStyle(.red)
            Button("다시 불러오기") { model.load() }
          }
          if model.uncertainMutation {
            Button("재전송 없이 초안 정리") { model.abandonUncertainMutation() }
          }
          Text(model.selectedDay, format: .dateTime.month().day().weekday(.wide))
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
          let dayEvents = model.events(on: model.selectedDay)
          if dayEvents.isEmpty && !model.isLoading && model.notice == nil {
            emptyDayCard
          }
          ForEach(dayEvents) { event in
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
          .disabled(model.requiresNavigationProtection)
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

  private var monthCard: some View {
    VStack(spacing: WoorisaiSpacing.xSmall) {
      HStack(spacing: 0) {
        monthArrow(-1, symbol: "chevron.left", label: "이전 달")
        Text(model.displayedMonth, format: .dateTime.year().month(.wide))
          .font(.headline)
          .frame(maxWidth: .infinity)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("calendar.month")
        monthArrow(1, symbol: "chevron.right", label: "다음 달")
      }
      ZStack(alignment: .top) {
        monthGrid
          .id(model.displayedMonth)
          .transition(reduceMotion ? .identity : .asymmetric(
            insertion: .offset(x: 56 * monthDirection).combined(with: .opacity),
            removal: .opacity
          ))
      }
      .clipped()
      .animation(reduceMotion ? nil : .easeOut(duration: 0.23), value: model.displayedMonth)

      Button { goToToday() } label: {
        Label("오늘", systemImage: "calendar")
          .font(.subheadline.weight(.semibold))
          .padding(.horizontal, WoorisaiSpacing.medium)
          .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
          .contentShape(Rectangle())
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
      .accessibilityIdentifier("calendar.today")
    }
    .padding(WoorisaiSpacing.small)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: WoorisaiRadius.medium))
    .contentShape(Rectangle())
    .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
      let delta = value.translation
      guard abs(delta.width) >= 44, abs(delta.width) > abs(delta.height) * 1.5 else { return }
      changeMonth(by: delta.width < 0 ? 1 : -1)
    })
  }

  private var monthGrid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WoorisaiSpacing.xSmall), count: 7), spacing: WoorisaiSpacing.xSmall) {
      ForEach(0..<7, id: \.self) { index in
        Text(model.weekdaySymbols[index])
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      ForEach(0..<model.leadingEmptyDays, id: \.self) { _ in
        Color.clear.frame(height: WoorisaiControlMetric.minimumTapTarget)
      }
      ForEach(model.days, id: \.self) { day in
        let selected = day == model.selectedDay
        let today = Calendar.current.isDateInToday(day)
        let hasEvents = !model.events(on: day).isEmpty
        Button { model.select(day) } label: {
          VStack(spacing: WoorisaiSpacing.xSmall) {
            Text(day, format: .dateTime.day())
              .font(.subheadline.weight(selected || today ? .bold : .regular))
            Circle().fill(hasEvents ? Color.accentColor : .clear).frame(width: 5, height: 5)
          }
          .foregroundStyle(today && !selected ? Color.accentColor : Color.primary)
          .frame(maxWidth: .infinity, minHeight: WoorisaiControlMetric.minimumTapTarget)
          .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: WoorisaiRadius.small))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(today ? (hasEvents ? "오늘, 일정 있음" : "오늘") : (hasEvents ? "일정 있음" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
  }

  private var emptyDayCard: some View {
    Button { creating = true } label: {
      HStack(spacing: WoorisaiSpacing.medium) {
        Image(systemName: "calendar.badge.plus")
          .font(.title2)
          .foregroundStyle(Color.accentColor)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
          Text("이날은 일정이 없어요").font(.headline).foregroundStyle(.primary)
          Text("일정 추가하기").font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      .padding(WoorisaiSpacing.regular)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: WoorisaiRadius.medium))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("calendar.empty.add")
    .disabled(model.requiresNavigationProtection)
  }

  private func monthArrow(_ offset: Int, symbol: String, label: String) -> some View {
    Button { changeMonth(by: offset) } label: {
      Image(systemName: symbol)
        .font(.subheadline.weight(.semibold))
        .frame(width: WoorisaiControlMetric.minimumTapTarget, height: WoorisaiControlMetric.minimumTapTarget)
        .contentShape(Rectangle())
    }
    .accessibilityLabel(label)
  }

  private func changeMonth(by offset: Int) {
    monthDirection = offset > 0 ? 1 : -1
    model.changeMonth(by: offset)
  }

  private func goToToday() {
    let today = Date.now
    monthDirection = today < model.displayedMonth ? -1 : 1
    model.showDay(today)
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
          .onChange(of: startAt) { _, newStart in
            endAt = CalendarEditorDates.endAfterStartChange(newStart, previousEnd: endAt, allDay: allDay, calendar: .current)
          }
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
