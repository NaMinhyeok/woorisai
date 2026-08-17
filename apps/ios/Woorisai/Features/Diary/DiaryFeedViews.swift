import SwiftUI
import WoorisaiAPI

struct DiaryEntryCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let entry: DiaryEntry
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void

  var body: some View {
    WarmSurface(cornerRadius: WoorisaiRadius.large) {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.medium) {
        NavigationLink(value: entry.id) {
          VStack(alignment: .leading, spacing: WoorisaiSpacing.medium) {
            entryHeader

            Text(entry.content)
              .font(.body)
              .foregroundStyle(WoorisaiColor.Fg.neutral.opacity(0.9))
              .lineSpacing(4)
              .lineLimit(4)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("diary.entry.\(entry.id).open")

        if !entry.attachments.isEmpty {
          DiaryAttachmentGallery(
            attachments: entry.attachments,
            mediaService: mediaService,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }

        Divider()
          .overlay(WoorisaiColor.Stroke.neutralWeak)

        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
            entryMetadata
            conversationLink
          }
        } else {
          HStack(spacing: WoorisaiSpacing.medium) {
            entryMetadata
            Spacer(minLength: 0)
            conversationLink
          }
        }
      }
      .padding(WoorisaiSpacing.regular)
    }
    .overlay(alignment: .top) {
      DiaryPaperTape()
        .offset(y: -8)
    }
    .overlay {
      if entry.isMine {
        RoundedRectangle(cornerRadius: WoorisaiRadius.large, style: .continuous)
          .stroke(WoorisaiColor.stroke(.mine), lineWidth: 1)
      }
    }
    .padding(.top, WoorisaiSpacing.small)
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var entryHeader: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
        ParticipantAvatar(name: entry.author.displayName, size: 40)
        authorIdentity
      }
    } else {
      HStack(alignment: .top, spacing: WoorisaiSpacing.medium) {
        ParticipantAvatar(name: entry.author.displayName, size: 40)
        authorIdentity
        Spacer(minLength: WoorisaiSpacing.small)
        Image(systemName: "heart.fill")
          .font(.caption)
          .foregroundStyle(WoorisaiColor.fg(.init(isMine: entry.isMine)))
          .padding(.top, WoorisaiSpacing.small)
          .accessibilityHidden(true)
      }
    }
  }

  private var authorIdentity: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      HStack(spacing: WoorisaiSpacing.small) {
        Text(entry.author.displayName)
          .font(.headline)
          .foregroundStyle(WoorisaiColor.Fg.neutral)
          .fixedSize(horizontal: false, vertical: true)
        if entry.isMine {
          Text("내 기록")
            .font(.caption2.weight(.bold))
            .foregroundStyle(WoorisaiColor.Fg.brand)
            .padding(.horizontal, WoorisaiSpacing.small)
            .padding(.vertical, WoorisaiSpacing.xSmall)
            .background(WoorisaiColor.Bg.brandWeak, in: Capsule())
        }
      }
      Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
        .font(.caption)
        .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
    }
  }

  private var entryMetadata: some View {
    HStack(spacing: WoorisaiSpacing.medium) {
      if !entry.attachments.isEmpty {
        Label("첨부 \(entry.attachments.count)", systemImage: "paperclip")
      }
      Label("댓글 \(entry.commentCount)", systemImage: "bubble.left")
    }
    .font(.caption)
    .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
  }

  private var conversationLink: some View {
    NavigationLink(value: entry.id) {
      Label("대화 보기", systemImage: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(WoorisaiColor.Fg.brand)
        .frame(
          maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
          minHeight: WoorisaiControlMetric.minimumTapTarget,
          alignment: .leading
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("diary.entry.\(entry.id).conversation")
  }
}

struct DiaryAttachmentGallery: View {
  let attachments: [DiaryAttachment]
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void

  var body: some View {
    MediaAttachmentPreviewGallery(
      attachments: attachments.map(MediaAttachmentDescriptor.init),
      onAuthenticationRequired: onAuthenticationRequired
    )
    .accessibilityIdentifier("media.group")
  }
}

extension MediaAttachmentDescriptor {
  init(_ attachment: DiaryAttachment) {
    self.init(
      id: attachment.id,
      fileName: attachment.fileName,
      contentType: attachment.contentType,
      byteSize: attachment.byteSize
    )
  }
}

struct DiaryPaperTape: View {
  var body: some View {
    RoundedRectangle(cornerRadius: WoorisaiRadius.xSmall, style: .continuous)
      .fill(WoorisaiColor.Decor.tapeFill)
      .frame(width: 62, height: 16)
      .rotationEffect(.degrees(-2))
      .overlay {
        Rectangle()
          .stroke(WoorisaiColor.Decor.tapeEdge, style: StrokeStyle(dash: [3, 3]))
      }
      .accessibilityHidden(true)
  }
}

struct DiaryHero: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let eyebrow: LocalizedStringKey
  let title: LocalizedStringKey
  let message: LocalizedStringKey
  let symbol: String

  var body: some View {
    WarmSurface(cornerRadius: WoorisaiRadius.large) {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
            heroSymbol
            heroCopy
          }
        } else {
          HStack(spacing: WoorisaiSpacing.medium) {
            heroSymbol
            heroCopy
            Spacer(minLength: 0)
          }
        }
      }
      .padding(WoorisaiSpacing.regular)
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }

  private var heroSymbol: some View {
    Image(systemName: symbol)
      .font(.system(size: 22, weight: .semibold))
      .foregroundStyle(WoorisaiColor.Fg.brandVivid)
      .frame(
        width: WoorisaiControlMetric.minimumTapTarget,
        height: WoorisaiControlMetric.minimumTapTarget
      )
      .background(WoorisaiColor.Bg.brandWeak, in: Circle())
      .accessibilityHidden(true)
  }

  private var heroCopy: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      Eyebrow(eyebrow)
      Text(title)
        .font(.title2.weight(.bold))
        .foregroundStyle(WoorisaiColor.Fg.neutral)
      Text(message)
        .font(.callout)
        .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
