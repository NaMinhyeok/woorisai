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
              linksToThread: true
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
            .foregroundStyle(WoorisaiColor.Fg.brand)
            .padding(.vertical, WoorisaiSpacing.xSmall)
            .background(
              WoorisaiColor.Bg.brandWeak,
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
          .foregroundStyle(WoorisaiColor.Fg.critical)
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
        .tint(WoorisaiColor.Fg.brand)
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
    HStack(alignment: .top, spacing: WoorisaiSpacing.small) {
      VStack(spacing: 0) {
        Circle()
          .fill(WoorisaiColor.Bg.brandVivid)
          .frame(width: 12, height: 12)
          .overlay {
            Circle()
              .stroke(WoorisaiColor.Bg.layerBasement, lineWidth: 3)
          }
          .padding(.top, WoorisaiSpacing.large)

        if !isLast {
          Rectangle()
            .fill(WoorisaiColor.Stroke.neutralWeak)
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
        linksToThread: true
      )
      .padding(.bottom, isLast ? 0 : WoorisaiSpacing.medium)
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
  var linksToThread = false

  var body: some View {
    if linksToThread {
      // The whole card is the tap target: users tap the comment badge or the body expecting
      // to land in the conversation, so a single bottom link row is not enough.
      NavigationLink(value: RelationshipDestination.scoreThread(change.id)) {
        card
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("relationship.history.\(change.id)")
    } else {
      card
    }
  }

  private var card: some View {
    let headerLayout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: WoorisaiSpacing.small))
      : AnyLayout(HStackLayout(alignment: .top, spacing: WoorisaiSpacing.small))
    let footerLayout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: WoorisaiSpacing.small))
      : AnyLayout(HStackLayout(alignment: .center, spacing: WoorisaiSpacing.medium))

    return WarmSurface {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.medium) {
        headerLayout {
          VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
            Text(
              "\(change.sourceParticipant.displayName)  →  \(change.targetParticipant.displayName)"
            )
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(WoorisaiColor.Fg.neutral)
            Text(change.createdAt.formatted(date: .abbreviated, time: .shortened))
              .font(.caption2)
              .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
          }
          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: WoorisaiSpacing.small)
          }
          WoorisaiDeltaBadge(change.delta)
        }

        if let reason = change.reason {
          Text("“\(reason)”")
            .font(.body)
            .foregroundStyle(WoorisaiColor.Fg.neutral.opacity(0.88))
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
          .overlay(WoorisaiColor.Stroke.neutralWeak)

        footerLayout {
          Label("변경 후 \(change.resultingScore)점", systemImage: "heart.fill")
          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: WoorisaiSpacing.xSmall)
          }
          if !change.attachments.isEmpty {
            Label("첨부 \(change.attachments.count)", systemImage: "paperclip")
          }
          Label("댓글 \(change.commentCount)", systemImage: "bubble.left")
        }
        .font(.caption)
        .foregroundStyle(WoorisaiColor.Fg.neutralMuted)

        if linksToThread {
          HStack {
            Text("전체 내용과 대화 보기")
            Spacer()
            Image(systemName: "chevron.right")
              .accessibilityHidden(true)
          }
          .font(.subheadline.weight(.bold))
          .foregroundStyle(WoorisaiColor.Fg.brand)
          .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
          // 간격이 아니라 광학 정렬이다. 위 텍스트 블록의 baseline에 맞추려고 2pt 내린 것이라
          // `WoorisaiSpacing` 스케일에 올리지 않는다.
          .padding(.top, 2)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(WoorisaiSpacing.regular)
    }
    .accessibilityElement(children: .contain)
  }
}
