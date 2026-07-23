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
              .foregroundStyle(WoorisaiPalette.ink.opacity(0.9))
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
          .overlay(WoorisaiPalette.line)

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
          .stroke(WoorisaiPalette.coral.opacity(0.24), lineWidth: 1)
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
          .foregroundStyle(entry.isMine ? WoorisaiPalette.coral : WoorisaiPalette.sage)
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
          .foregroundStyle(WoorisaiPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
        if entry.isMine {
          Text("내 기록")
            .font(.caption2.weight(.bold))
            .foregroundStyle(WoorisaiPalette.coralDark)
            .padding(.horizontal, WoorisaiSpacing.small)
            .padding(.vertical, WoorisaiSpacing.xSmall)
            .background(WoorisaiPalette.coralSoft, in: Capsule())
        }
      }
      Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
        .font(.caption)
        .foregroundStyle(WoorisaiPalette.muted)
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
    .foregroundStyle(WoorisaiPalette.muted)
  }

  private var conversationLink: some View {
    NavigationLink(value: entry.id) {
      Label("대화 보기", systemImage: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(WoorisaiPalette.coralDark)
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
    MediaAttachmentGallery(
      items: attachments,
      kind: { $0.contentType.lowercased().hasPrefix("image/") ? .image : .video }
    ) { attachment, format in
      MediaAttachmentPreview(
        attachmentID: attachment.id,
        fileName: attachment.fileName,
        contentType: attachment.contentType,
        byteSize: attachment.byteSize,
        tileFormat: format,
        onAuthenticationRequired: onAuthenticationRequired
      )
    }
    .accessibilityIdentifier("media.group")
  }
}

struct DiaryPaperTape: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 3, style: .continuous)
      .fill(WoorisaiPalette.sageSoft.opacity(0.92))
      .frame(width: 62, height: 16)
      .rotationEffect(.degrees(-2))
      .overlay {
        Rectangle()
          .stroke(WoorisaiPalette.sage.opacity(0.2), style: StrokeStyle(dash: [3, 3]))
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
      .foregroundStyle(WoorisaiPalette.coral)
      .frame(width: 44, height: 44)
      .background(WoorisaiPalette.coralSoft, in: Circle())
      .accessibilityHidden(true)
  }

  private var heroCopy: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      Eyebrow(eyebrow)
      Text(title)
        .font(.title2.weight(.bold))
        .foregroundStyle(WoorisaiPalette.ink)
      Text(message)
        .font(.callout)
        .foregroundStyle(WoorisaiPalette.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
