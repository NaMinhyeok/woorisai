import SwiftUI
import WoorisaiAPI

struct DiaryEntryCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let entry: DiaryEntry
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
      NavigationLink(value: entry.id) {
        HStack(alignment: .top, spacing: WoorisaiSpacing.medium) {
          VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
            Text(entry.createdAt, format: .dateTime.month().day().weekday(.abbreviated))
              .font(.caption.weight(.semibold))
              .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
            Text(entry.content.isEmpty ? "사진과 첨부를 남긴 일기" : entry.content)
              .font(.body)
              .foregroundStyle(WoorisaiColor.Fg.neutral)
              .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 4)
            ViewThatFits(in: .horizontal) {
              HStack(spacing: WoorisaiSpacing.small) { author; counters }
                .fixedSize(horizontal: true, vertical: false)
              VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) { author; counters }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
            .accessibilityHidden(true)
        }
        .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("diary.entry.\(entry.id).open")

      // Media has a different action from reading the entry, so it stays outside the link.
      if !entry.attachments.isEmpty {
        DiaryAttachmentGallery(
          attachments: entry.attachments,
          mediaService: mediaService,
          onAuthenticationRequired: onAuthenticationRequired
        )
      }
    }
    .padding(.vertical, WoorisaiSpacing.small)
    .overlay(alignment: .bottom) { Divider().accessibilityHidden(true) }
    .accessibilityElement(children: .contain)
  }

  private var author: some View {
    Text(entry.isMine ? "\(entry.author.displayName) · 내 기록" : entry.author.displayName)
      .font(.footnote.weight(.semibold))
      .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
  }

  private var counters: some View {
    HStack(spacing: WoorisaiSpacing.small) {
      if !entry.attachments.isEmpty {
        Label("첨부 \(entry.attachments.count)", systemImage: "paperclip")
      }
      Label("댓글 \(entry.commentCount)", systemImage: "bubble.left")
    }
    .font(.caption)
    .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
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

  @ViewBuilder
  private var heroSymbol: some View {
    if symbol == "book.pages.fill" {
      WoorisaiCompanions(size: 70)
    } else {
      Image(systemName: symbol)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(WoorisaiColor.Fg.brandVivid)
        .frame(width: 52, height: 52)
        .background(WoorisaiColor.Bg.brandWeak, in: Circle())
        .accessibilityHidden(true)
    }
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
