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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State var model: CalendarModel
  let participant: AuthenticatedParticipant
  @State private var detailID: Int64?
  @State private var editor: CalendarEvent?
  @State private var creating = false
  @State private var deleting: CalendarEvent?
  @State private var monthDirection: CGFloat = 1

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        ScrollView {
          VStack(alignment: .leading, spacing: WoorisaiSpacing.regular) {
            monthCard(rowHeight: monthRowHeight(in: geometry.size.height))
            if model.dayPanel == .hidden { calendarStatus }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, WoorisaiSpacing.small)
          .padding(.vertical, WoorisaiSpacing.small)
          .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if model.dayPanel != .hidden {
            dayPanel(maximumListHeight: geometry.size.height * 0.34)
              .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
          }
        }
      }
      .background(WoorisaiColor.Bg.layerBasement.ignoresSafeArea())
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(item: $detailID) { id in
        eventDetail(id)
          .toolbar(.visible, for: .navigationBar)
          .navigationBarTitleDisplayMode(.inline)
      }
      .task { if !model.isLoading && model.events.isEmpty { model.load() } }
    }
    .sheet(isPresented: $creating) {
      CalendarEditor(model: model, event: nil, participant: participant)
    }
    .sheet(item: $editor) { event in
      CalendarEditor(model: model, event: event, participant: participant)
    }
    .confirmationDialog("일정을 삭제할까요?", isPresented: Binding(
      get: { deleting != nil }, set: { if !$0 { deleting = nil } }
    ), titleVisibility: .visible) {
      Button("삭제", role: .destructive) {
        if let deleting { model.delete(deleting, as: participant.slot) }
        deleting = nil
      }
      Button("취소", role: .cancel) {}
    }
    .onChange(of: model.externalSelectionRevision) { _, _ in detailID = nil }
    .onChange(of: model.events.map(\.id)) { _, ids in
      if let detailID, !ids.contains(detailID) { self.detailID = nil }
    }
  }

  @ViewBuilder
  private var calendarStatus: some View {
    if model.isLoading { ProgressView("일정을 불러오는 중이에요") }
    if let notice = model.notice {
      Text(notice).foregroundStyle(WoorisaiColor.Fg.critical)
      Button("다시 불러오기") { model.load() }
    }
    if model.uncertainMutation {
      Button("재전송 없이 초안 정리") { model.abandonUncertainMutation() }
    }
  }

  private var createButton: some View {
    Button { creating = true } label: {
      Image(systemName: "plus")
        .font(.body.weight(.semibold))
        .frame(width: WoorisaiControlMetric.minimumTapTarget, height: WoorisaiControlMetric.minimumTapTarget)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("일정 추가")
    .accessibilityIdentifier("calendar.create")
    .disabled(model.requiresNavigationProtection)
  }

  private func dayPanel(maximumListHeight: CGFloat) -> some View {
    let events = model.events(on: model.selectedDay)
    let expanded = model.dayPanel == .expanded
    return VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      disclosure(eventCount: events.count, expanded: expanded)
      if model.notice != nil || model.uncertainMutation {
        calendarStatus
      } else if model.isLoading && events.isEmpty {
        ProgressView("선택한 날 확인 중")
          .font(.subheadline)
      } else if events.isEmpty {
        emptyDayCard
      } else if expanded {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(events) { event in
              eventRow(event)
              if event.id != events.last?.id { Divider() }
            }
          }
        }
        .frame(maxHeight: maximumListHeight)
      } else if let first = events.first {
        eventRow(first)
      }
    }
    .padding(.horizontal, WoorisaiSpacing.screenGutter)
    .padding(.bottom, WoorisaiSpacing.small)
    .frame(maxWidth: 680)
    .frame(maxWidth: .infinity, alignment: .center)
    .background(WoorisaiColor.Bg.layerDefault)
    .overlay(alignment: .top) { Divider().accessibilityHidden(true) }
  }

  private func disclosure(eventCount: Int, expanded: Bool) -> some View {
    Button {
      setPanel(expanded ? .compact : .expanded)
    } label: {
      VStack(spacing: WoorisaiSpacing.xSmall) {
        Capsule().fill(WoorisaiColor.Fg.neutralMuted.opacity(0.5))
          .frame(width: 32, height: 4)
          .accessibilityHidden(true)
        HStack(alignment: .firstTextBaseline, spacing: WoorisaiSpacing.small) {
          Text(model.selectedDay, format: .dateTime.month().day().weekday(.wide))
            .font(.headline)
          if !model.isLoading && model.notice == nil {
            Text("\(eventCount)건").font(.subheadline).foregroundStyle(WoorisaiColor.Fg.neutralMuted)
          }
          Spacer(minLength: 0)
          Image(systemName: expanded ? "chevron.down" : "chevron.up")
            .font(.caption.weight(.semibold)).accessibilityHidden(true)
        }
      }
      .padding(.top, WoorisaiSpacing.small)
      .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityValue(expanded ? "펼쳐짐" : "접힘")
    .accessibilityHint(expanded ? "선택한 날 일정을 접습니다." : "선택한 날 일정을 펼칩니다.")
    .accessibilityIdentifier("calendar.day.disclosure")
    .simultaneousGesture(DragGesture(minimumDistance: 15).onEnded { value in
      let delta = value.translation
      guard abs(delta.height) > abs(delta.width), abs(delta.height) >= 25 else { return }
      if delta.height < 0 { setPanel(.expanded) }
      else { setPanel(expanded ? .compact : .hidden) }
    })
    .accessibilityAction(named: Text("미리보기 닫기")) { setPanel(.hidden) }
  }

  private func setPanel(_ panel: CalendarModel.DayPanel) {
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { model.setDayPanel(panel) }
  }

  private func inspect(_ day: Date) {
    if model.dayPanel == .hidden {
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { model.inspect(day) }
    } else {
      model.inspect(day)
    }
  }

  private func eventRow(_ event: CalendarEvent) -> some View {
    Button { detailID = event.id } label: {
      HStack(spacing: WoorisaiSpacing.medium) {
        VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
          Text(event.title).font(.body.weight(.semibold)).foregroundStyle(WoorisaiColor.Fg.neutral)
            .lineLimit(model.dayPanel == .compact ? 1 : nil)
          Text("\(eventTime(event)) · \(eventKind(event))")
            .font(.footnote).foregroundStyle(WoorisaiColor.Fg.neutralMuted)
            .lineLimit(model.dayPanel == .compact ? 1 : nil)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
      }
      .padding(.vertical, WoorisaiSpacing.xSmall)
      .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("calendar.event.\(event.id)")
  }

  @ViewBuilder
  private func eventDetail(_ id: Int64) -> some View {
    if let event = model.events.first(where: { $0.id == id }) {
      List {
        Section {
          LabeledContent("시작", value: event.startAt.formatted(date: .abbreviated, time: event.allDay ? .omitted : .shortened))
          let end = CalendarEditorDates.displayedEnd(event.endAt, allDay: event.allDay, calendar: .current)
          LabeledContent("종료", value: end.formatted(date: .abbreviated, time: event.allDay ? .omitted : .shortened))
          LabeledContent("구분", value: eventKind(event))
          LabeledContent("작성자", value: event.author.displayName)
        }
        if let note = event.note, !note.isEmpty {
          Section("메모") { Text(note) }
        }
        if event.canEdit(as: participant.slot) {
          Section {
            Button("일정 삭제", role: .destructive) { deleting = event }
              .disabled(model.requiresNavigationProtection)
          }
        }
        if model.notice != nil || model.uncertainMutation {
          Section { calendarStatus }
        }
      }
      .navigationTitle(event.title)
      .accessibilityIdentifier("calendar.event.detail")
      .toolbar {
        if event.canEdit(as: participant.slot) {
          ToolbarItem(placement: .topBarTrailing) {
            Button("편집") { editor = event }
              .disabled(model.requiresNavigationProtection)
              .accessibilityIdentifier("calendar.event.edit")
          }
        }
      }
    } else {
      ContentUnavailableView("일정을 찾을 수 없어요", systemImage: "calendar")
    }
  }

  private func eventTime(_ event: CalendarEvent) -> String {
    if event.allDay { return "종일" }
    if event.startAt < model.selectedDay { return "전날부터" }
    return event.startAt.formatted(date: .omitted, time: .shortened)
  }

  private func eventKind(_ event: CalendarEvent) -> String {
    if event.kind == .ours { return "우리 일정" }
    return event.author.slot == participant.slot ? "내 일정" : "상대 일정"
  }

  private func monthRowHeight(in height: CGFloat) -> CGFloat {
    let weeks = max(1, (model.leadingEmptyDays + model.days.count + 6) / 7)
    let reserved: CGFloat = model.dayPanel == .hidden ? 108 : 244
    return max(44, min(112, (height - reserved) / CGFloat(weeks)))
  }

  private func monthCard(rowHeight: CGFloat) -> some View {
    VStack(spacing: WoorisaiSpacing.xSmall) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 0) {
          monthLabel.fixedSize(horizontal: true, vertical: false)
          Spacer(minLength: WoorisaiSpacing.small)
          monthControls.fixedSize(horizontal: true, vertical: false)
        }
        VStack(alignment: .leading, spacing: 0) {
          monthLabel
          monthControls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.leading, WoorisaiSpacing.small)
      ZStack(alignment: .top) {
        monthGrid(rowHeight: rowHeight)
          .id(model.displayedMonth)
          .transition(reduceMotion ? .identity : .asymmetric(
            insertion: .offset(x: 56 * monthDirection).combined(with: .opacity),
            removal: .opacity
          ))
      }
      .clipped()
      .animation(reduceMotion ? nil : .easeOut(duration: 0.23), value: model.displayedMonth)

    }
    .contentShape(Rectangle())
    .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
      let delta = value.translation
      guard abs(delta.width) >= 44, abs(delta.width) > abs(delta.height) * 1.5 else { return }
      changeMonth(by: delta.width < 0 ? 1 : -1)
    })
  }

  private var monthLabel: some View {
    Text(model.displayedMonth, format: .dateTime.year().month(.wide))
      .font(.title3.bold())
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("calendar.month")
  }

  private var monthControls: some View {
    HStack(spacing: 0) {
      monthArrow(-1, symbol: "chevron.left", label: "이전 달")
      Button("오늘") { goToToday() }
        .font(.subheadline.weight(.semibold))
        .frame(minWidth: WoorisaiControlMetric.minimumTapTarget, minHeight: WoorisaiControlMetric.minimumTapTarget)
        .accessibilityIdentifier("calendar.today")
      monthArrow(1, symbol: "chevron.right", label: "다음 달")
      createButton
    }
  }

  private func monthGrid(rowHeight: CGFloat) -> some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
      ForEach(0..<7, id: \.self) { index in
        Text(model.weekdaySymbols[index])
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      ForEach(0..<model.leadingEmptyDays, id: \.self) { _ in
        Color.clear.frame(height: rowHeight)
          .accessibilityHidden(true)
      }
      ForEach(model.days, id: \.self) { day in
        let selected = day == model.selectedDay
        let today = Calendar.current.isDateInToday(day)
        let events = model.events(on: day)
        let eventCount = events.count
        Button { inspect(day) } label: {
          VStack(spacing: 2) {
            Text(day, format: .dateTime.day())
              .font(.subheadline.weight(selected || today ? .bold : .regular))
              .minimumScaleFactor(0.65)
              .lineLimit(1)
            Text(dayPreview(events))
              .font(.caption2.weight(.semibold))
              .foregroundStyle(WoorisaiColor.Fg.brand)
              .minimumScaleFactor(0.55)
              .lineLimit(1)
              .accessibilityHidden(true)
          }
          .foregroundStyle(today && !selected ? Color.accentColor : Color.primary)
          .frame(maxWidth: .infinity, minHeight: rowHeight)
          .background(selected ? WoorisaiColor.Bg.selected : .clear, in: RoundedRectangle(cornerRadius: WoorisaiRadius.small))
          .overlay {
            if today {
              RoundedRectangle(cornerRadius: WoorisaiRadius.small).strokeBorder(WoorisaiColor.Fg.brand)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue([today ? "오늘" : nil, eventCount > 0 ? "일정 \(eventCount)개" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("calendar.day.cell.\(day.timeIntervalSinceReferenceDate)")
      }
    }
  }

  private func dayPreview(_ events: [CalendarEvent]) -> String {
    guard let first = events.first else { return " " }
    if dynamicTypeSize >= .xxxLarge || events.count > 1 { return "\(events.count)건" }
    return first.title
  }

  private var emptyDayCard: some View {
    Button { creating = true } label: {
      Label("일정 없음 · 이날에 추가", systemImage: "calendar.badge.plus")
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: WoorisaiControlMetric.minimumTapTarget, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(WoorisaiColor.Fg.brand)
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
    inspect(today)
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
        if wasMutating && !mutating && model.notice == nil {
          model.setDayPanel(.expanded)
          dismiss()
        }
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
