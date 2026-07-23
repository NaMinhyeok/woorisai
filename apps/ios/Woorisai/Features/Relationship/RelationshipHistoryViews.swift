import SwiftUI
import WoorisaiAPI

struct RelationshipHistoryArchiveView: View {
  @State private var model: RelationshipModel
  @AccessibilityFocusState private var isPagingNoticeFocused: Bool

  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void

  @MainActor
  init(
    model: RelationshipModel,
    mediaService: any MediaServing,
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    _model = State(initialValue: model)
    self.mediaService = mediaService
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  var body: some View {
    WarmBackground {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: WoorisaiSpacing.medium) {
          WoorisaiSectionHeading(
            "차곡차곡 쌓인 마음",
            detail: "\(model.totalCount)개",
            symbol: "heart.text.square.fill"
          )

          ForEach(model.changes) { change in
            ScoreChangeRow(
              change: change,
              mediaService: mediaService,
              onAuthenticationRequired: onAuthenticationRequired,
              reasonDisplay: .historySummary,
              navigationValue: change.id
            )
          }

          if let archiveNotice = model.archiveNotice {
            archiveNoticeCard(archiveNotice)
          }

          if model.hasNextPage {
            Button {
              model.loadNextPage()
            } label: {
              HStack(spacing: WoorisaiSpacing.small) {
                if model.pagingState == .loading {
                  ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                }
                Text(
                  model.pagingState == .loading ? "이전 기록 불러오는 중" : "이전 기록 더 불러오기"
                )
              }
              .frame(maxWidth: .infinity, minHeight: WoorisaiControlMetric.minimumTapTarget)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(WoorisaiPalette.coralDark)
            .padding(.vertical, WoorisaiSpacing.xSmall)
            .background(
              WoorisaiPalette.coralSoft,
              in: RoundedRectangle(cornerRadius: WoorisaiRadius.small)
            )
            .disabled(model.pagingState == .loading)
            .accessibilityIdentifier("relationship.history.nextPage")
          }
        }
        .frame(maxWidth: 680)
        .padding(.horizontal, WoorisaiSpacing.screenGutter)
        .padding(.top, WoorisaiSpacing.small)
        .padding(.bottom, WoorisaiSpacing.xLarge)
        .frame(maxWidth: .infinity)
      }
      .refreshable {
        await model.refresh()
      }
    }
    .navigationTitle("마음 기록")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier("relationship.history.archive")
    .onChange(of: model.pagingState) { _, state in
      if state == .failed {
        isPagingNoticeFocused = true
      }
    }
  }

  private func archiveNoticeCard(_ message: String) -> some View {
    WarmSurface(cornerRadius: WoorisaiRadius.medium) {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .font(.callout.weight(.semibold))
          .foregroundStyle(WoorisaiPalette.error)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("relationship.history.noticeMessage")
          .accessibilityFocused($isPagingNoticeFocused)
        Button(model.pagingState == .failed ? "다시 불러오기" : "새로고침") {
          if model.pagingState == .failed {
            model.loadNextPage()
          } else {
            Task { await model.refresh() }
          }
        }
        .buttonStyle(.bordered)
        .tint(WoorisaiPalette.coralDark)
        .disabled(model.pagingState == .loading)
        .accessibilityIdentifier("relationship.history.retry")
      }
      .padding(WoorisaiSpacing.regular)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("relationship.history.notice")
  }
}

struct HistoryTimelineRow: View {
  let change: RelationshipScoreChange
  let isLast: Bool
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(spacing: 0) {
        Circle()
          .fill(WoorisaiPalette.coral)
          .frame(width: 12, height: 12)
          .overlay {
            Circle()
              .stroke(WoorisaiPalette.cream, lineWidth: 3)
          }
          .padding(.top, 22)

        if !isLast {
          Rectangle()
            .fill(WoorisaiPalette.line)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
        }
      }
      .frame(width: 16)

      ScoreChangeRow(
        change: change,
        mediaService: mediaService,
        onAuthenticationRequired: onAuthenticationRequired,
        reasonDisplay: .historySummary,
        navigationValue: change.id
      )
      .padding(.bottom, isLast ? 0 : 12)
    }
  }
}

enum ScoreChangeReasonDisplay {
  case historySummary
  case threadDetail

  var lineLimit: Int? {
    switch self {
    case .historySummary: 4
    case .threadDetail: nil
    }
  }

  func accessibilityIdentifier(changeID: Int64) -> String {
    switch self {
    case .historySummary: "relationship.history.reason.\(changeID)"
    case .threadDetail: "relationship.thread.reason.\(changeID)"
    }
  }
}

struct ScoreChangeRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let change: RelationshipScoreChange
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void
  let reasonDisplay: ScoreChangeReasonDisplay
  var navigationValue: Int64? = nil

  var body: some View {
    let headerLayout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
    let footerLayout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

    return WarmSurface {
      VStack(alignment: .leading, spacing: 14) {
        headerLayout {
          VStack(alignment: .leading, spacing: 4) {
            Text(
              "\(change.sourceParticipant.displayName)  →  \(change.targetParticipant.displayName)"
            )
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(WoorisaiPalette.ink)
            Text(change.createdAt.formatted(date: .abbreviated, time: .shortened))
              .font(.caption2)
              .foregroundStyle(WoorisaiPalette.muted)
          }
          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: 8)
          }
          Text(change.delta > 0 ? "+\(change.delta)점" : "\(change.delta)점")
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(
              change.delta > 0 ? WoorisaiPalette.coralDark : WoorisaiPalette.sage
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
              change.delta > 0 ? WoorisaiPalette.coralSoft : WoorisaiPalette.sageSoft,
              in: RoundedRectangle(cornerRadius: 11)
            )
            .fixedSize(horizontal: true, vertical: true)
        }

        if let reason = change.reason {
          Text("“\(reason)”")
            .font(.body)
            .foregroundStyle(WoorisaiPalette.ink.opacity(0.88))
            .lineLimit(reasonDisplay.lineLimit)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(
              reasonDisplay.accessibilityIdentifier(changeID: change.id)
            )
        }

        if !change.attachments.isEmpty {
          RelationshipMediaGallery(
            attachments: change.attachments,
            mediaService: mediaService,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }

        Divider()
          .overlay(WoorisaiPalette.line)

        footerLayout {
          Label("변경 후 \(change.resultingScore)점", systemImage: "heart.fill")
          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: 4)
          }
          if !change.attachments.isEmpty {
            Label("첨부 \(change.attachments.count)", systemImage: "paperclip")
          }
          Label("댓글 \(change.commentCount)", systemImage: "bubble.left")
        }
        .font(.caption)
        .foregroundStyle(WoorisaiPalette.muted)

        if let navigationValue {
          NavigationLink(value: navigationValue) {
            HStack {
              Text("전체 내용과 대화 보기")
              Spacer()
              Image(systemName: "chevron.right")
                .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(WoorisaiPalette.coralDark)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .padding(.top, 2)
          }
          .accessibilityIdentifier("relationship.history.\(change.id)")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
    }
    .accessibilityElement(children: .contain)
  }
}
