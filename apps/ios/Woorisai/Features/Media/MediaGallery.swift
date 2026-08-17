import SwiftUI
import UIKit
import WoorisaiAPI

enum MediaInlineTileFormat: Equatable, Sendable {
  case singleImage
  case mosaic
  case video

  var aspectRatio: CGFloat {
    switch self {
    case .singleImage:
      4 / 3
    case .mosaic:
      1
    case .video:
      16 / 9
    }
  }

  /// Decode budget per tile role. A 2-column mosaic cell renders ~170pt (~510px @3x); decoding
  /// every cell at the global 1,200px ceiling held ~4× the pixels a 4-image comment needs and
  /// pushed long threads toward jetsam on older devices. The full-screen viewer re-decodes the
  /// original separately, so tiles never need more than their own display size.
  var decodeMaxPixelSize: Int {
    switch self {
    case .singleImage, .video:
      MediaImagePreview.maximumPixelSize
    case .mosaic:
      640
    }
  }
}

/// How an attachment group arranges itself inline.
///
/// A group of one keeps the shape that reads best for its kind — 4:3 for a photo, 16:9 for a
/// video. Past one the group becomes a square mosaic regardless of kinds, because a mixed group
/// has no single aspect ratio to honour and unequal cells would make position, not content, the
/// loudest thing on screen.
enum MediaGroupLayout: Equatable, Sendable {
  case empty
  case singleImage
  case mosaic(columns: Int)
  case video

  static func resolve(kinds: [MediaKind]) -> Self {
    guard let only = kinds.first else { return .empty }
    if kinds.count == 1 { return only == .video ? .video : .singleImage }
    return .mosaic(columns: kinds.count == 3 ? 3 : 2)
  }
}

enum MediaFillGeometry {
  static func renderedSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
    guard imageSize.width.isFinite, imageSize.height.isFinite,
      containerSize.width.isFinite, containerSize.height.isFinite,
      imageSize.width > 0, imageSize.height > 0,
      containerSize.width > 0, containerSize.height > 0
    else {
      return .zero
    }

    let scale = max(
      containerSize.width / imageSize.width,
      containerSize.height / imageSize.height
    )
    return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
  }
}

struct MediaAttachmentGallery<Item: Identifiable, Tile: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let items: [Item]
  let kind: (Item) -> MediaKind
  private let tile: (Item, MediaInlineTileFormat) -> Tile

  init(
    items: [Item],
    kind: @escaping (Item) -> MediaKind,
    @ViewBuilder tile: @escaping (Item, MediaInlineTileFormat) -> Tile
  ) {
    self.items = items
    self.kind = kind
    self.tile = tile
  }

  @ViewBuilder
  var body: some View {
    switch MediaGroupLayout.resolve(kinds: items.map(kind)) {
    case .empty:
      EmptyView()
    case .singleImage:
      if let item = items.first {
        tile(item, .singleImage)
          .aspectRatio(MediaInlineTileFormat.singleImage.aspectRatio, contentMode: .fit)
          .id(item.id)
      }
    case .mosaic(let columnCount):
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: WoorisaiControlMetric.mediaGap),
          count: dynamicTypeSize.isAccessibilitySize ? min(columnCount, 2) : columnCount
        ),
        spacing: WoorisaiControlMetric.mediaGap
      ) {
        ForEach(items) { item in
          tile(item, .mosaic)
            .aspectRatio(MediaInlineTileFormat.mosaic.aspectRatio, contentMode: .fit)
        }
      }
    case .video:
      if let item = items.first {
        tile(item, .video)
          .aspectRatio(MediaInlineTileFormat.video.aspectRatio, contentMode: .fit)
          .id(item.id)
      }
    }
  }
}

/// A stored attachment reduced to what the gallery and its viewer need.
///
/// The diary and relationship APIs each carry their own attachment row with its own kind enum.
/// Both describe the same thing to this layer, and the viewer has to page across a group without
/// caring which feature it came from, so callers map into this one shape instead of the gallery
/// growing a generic parameter per feature.
struct MediaAttachmentDescriptor: Identifiable, Equatable, Sendable {
  let id: UUID
  let fileName: String
  let contentType: String
  let byteSize: Int64

  var isImage: Bool {
    contentType.lowercased().hasPrefix("image/")
  }

  var kind: MediaKind {
    isImage ? .image : .video
  }
}

/// Inline gallery for stored attachments, and the owner of their full-screen viewer.
///
/// The viewer is presented here rather than by each tile because a tile-owned viewer only ever
/// knows its own attachment: paging to a sibling is impossible when the presented view was handed
/// one file, so every photo in a group cost a close and a re-open. Presenting once per group makes
/// the whole group the unit the viewer moves through.
struct MediaAttachmentPreviewGallery<TileOverlay: View>: View {
  let attachments: [MediaAttachmentDescriptor]
  let onAuthenticationRequired: @MainActor () -> Void
  private let tileOverlay: (MediaAttachmentDescriptor) -> TileOverlay

  @State private var openedAttachment: OpenedMediaAttachment?

  init(
    attachments: [MediaAttachmentDescriptor],
    onAuthenticationRequired: @escaping @MainActor () -> Void,
    @ViewBuilder tileOverlay: @escaping (MediaAttachmentDescriptor) -> TileOverlay
  ) {
    self.attachments = attachments
    self.onAuthenticationRequired = onAuthenticationRequired
    self.tileOverlay = tileOverlay
  }

  var body: some View {
    MediaAttachmentGallery(items: attachments, kind: \.kind) { attachment, format in
      MediaAttachmentPreview(
        descriptor: attachment,
        tileFormat: format,
        onAuthenticationRequired: onAuthenticationRequired,
        onOpenViewer: { openedAttachment = OpenedMediaAttachment(id: $0) }
      )
      .overlay(alignment: .topTrailing) {
        tileOverlay(attachment)
      }
    }
    .fullScreenCover(item: $openedAttachment) { opened in
      MediaAttachmentViewer(
        attachments: attachments,
        initialAttachmentID: opened.id,
        onAuthenticationRequired: onAuthenticationRequired,
        onClose: { openedAttachment = nil }
      )
    }
  }
}

extension MediaAttachmentPreviewGallery where TileOverlay == EmptyView {
  init(
    attachments: [MediaAttachmentDescriptor],
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    self.init(
      attachments: attachments,
      onAuthenticationRequired: onAuthenticationRequired,
      tileOverlay: { _ in EmptyView() }
    )
  }
}

/// `fullScreenCover(item:)` needs an `Identifiable` value, and the attachment the user tapped is
/// the whole state the presentation carries.
private struct OpenedMediaAttachment: Identifiable, Equatable {
  let id: UUID
}

struct MediaTileSurface<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(WoorisaiColor.Bg.layerSunken)
      .clipShape(RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
          .stroke(WoorisaiColor.Stroke.neutralWeak, lineWidth: 1)
      }
      .contentShape(RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous))
  }
}

struct MediaFillImageSurface: View {
  let image: UIImage

  var body: some View {
    GeometryReader { proxy in
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: proxy.size.width, height: proxy.size.height)
        .clipped()
    }
    .accessibilityHidden(true)
  }
}

/// Full-screen viewer for one attachment group.
///
/// The group, not the tapped file, is the unit: opening from any tile lands on that attachment and
/// the rest are a swipe away. The chrome — save, position, close — belongs to the shell rather
/// than the pages so it does not slide off with the photo underneath it.
struct MediaAttachmentViewer: View {
  let attachments: [MediaAttachmentDescriptor]
  let onAuthenticationRequired: @MainActor () -> Void
  let onClose: () -> Void

  @State private var selectedID: UUID
  /// One model for the whole viewer, because a Photos write cannot be cancelled and may outlive
  /// the page that started it. It names the attachment it wrote so a save begun on one photo does
  /// not report success over the next one.
  @State private var librarySaveModel = MediaLibrarySaveModel()
  /// Reported by each page once its lease resolves. The save affordance lives in the shell, which
  /// therefore needs the current page's verified file without owning the download itself.
  @State private var resolvedFiles: [UUID: URL] = [:]

  init(
    attachments: [MediaAttachmentDescriptor],
    initialAttachmentID: UUID,
    onAuthenticationRequired: @escaping @MainActor () -> Void,
    onClose: @escaping () -> Void
  ) {
    self.attachments = attachments
    self.onAuthenticationRequired = onAuthenticationRequired
    self.onClose = onClose
    _selectedID = State(initialValue: initialAttachmentID)
  }

  var body: some View {
    ZStack {
      WoorisaiColor.Bg.immersive.ignoresSafeArea()

      TabView(selection: $selectedID) {
        ForEach(attachments) { descriptor in
          MediaAttachmentViewerPage(
            descriptor: descriptor,
            isCurrent: descriptor.id == selectedID,
            onAuthenticationRequired: onAuthenticationRequired,
            onFileResolved: { resolvedFiles[descriptor.id] = $0 }
          )
          .tag(descriptor.id)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
    }
    .overlay(alignment: .topLeading) {
      saveControl
    }
    .overlay(alignment: .top) {
      positionIndicator
    }
    .overlay(alignment: .topTrailing) {
      closeButton
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("media.viewerGroup")
  }

  private var currentDescriptor: MediaAttachmentDescriptor? {
    attachments.first { $0.id == selectedID }
  }

  @ViewBuilder
  private var saveControl: some View {
    if let descriptor = currentDescriptor,
      let fileURL = resolvedFiles[descriptor.id],
      MediaLibrarySaveModel.supportsPhotoLibrary(contentType: descriptor.contentType)
    {
      MediaLibrarySaveControl(
        model: librarySaveModel,
        subjectID: descriptor.id,
        fileURL: fileURL,
        isImage: descriptor.isImage
      )
      .padding(WoorisaiSpacing.regular)
    }
  }

  /// Counts the group rather than drawing dots: the chrome sits over an arbitrary photo, and a
  /// row of low-contrast dots is the first thing to disappear against a bright one.
  ///
  /// It is also the group's only VoiceOver control. Hiding the pager's own index display leaves
  /// swiping as the sole way to change pages, so the counter carries an adjustable action —
  /// reading the position and moving through it are the same element.
  @ViewBuilder
  private var positionIndicator: some View {
    if attachments.count > 1, let position = currentPosition {
      Text("\(position) / \(attachments.count)")
        .font(.subheadline.monospacedDigit().weight(.semibold))
        .foregroundStyle(WoorisaiColor.Fg.staticWhite)
        .padding(.horizontal, WoorisaiSpacing.medium)
        .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
        .background(WoorisaiColor.Bg.scrim, in: Capsule())
        .padding(WoorisaiSpacing.regular)
        .accessibilityElement()
        .accessibilityLabel("첨부 \(attachments.count)개 중 \(position)번째")
        .accessibilityHint("위아래로 조절해 다른 첨부를 볼 수 있어요.")
        .accessibilityAdjustableAction { direction in
          switch direction {
          case .increment:
            moveSelection(by: 1)
          case .decrement:
            moveSelection(by: -1)
          @unknown default:
            return
          }
        }
        .accessibilityIdentifier("media.viewer.position")
    }
  }

  private var currentPosition: Int? {
    attachments.firstIndex { $0.id == selectedID }.map { $0 + 1 }
  }

  /// Clamped rather than wrapping: at the last attachment, "next" should report the end of the
  /// group instead of quietly returning to the first one.
  private func moveSelection(by offset: Int) {
    guard let index = attachments.firstIndex(where: { $0.id == selectedID }) else { return }
    let target = min(max(index + offset, 0), attachments.count - 1)
    guard target != index else { return }
    selectedID = attachments[target].id
  }

  private var closeButton: some View {
    Button(action: onClose) {
      Image(systemName: "xmark")
        .font(.body.weight(.bold))
        .foregroundStyle(WoorisaiColor.Fg.staticWhite)
        .frame(
          width: WoorisaiControlMetric.minimumTapTarget,
          height: WoorisaiControlMetric.minimumTapTarget
        )
        .background(WoorisaiColor.Bg.scrim, in: Circle())
    }
    .buttonStyle(.plain)
    .padding(WoorisaiSpacing.regular)
    .accessibilityLabel("전체 보기 닫기")
    .accessibilityIdentifier("media.viewer.close")
  }
}

/// One attachment inside ``MediaAttachmentViewer``.
///
/// Each page owns its own load so the shared preview store — which already de-duplicates by
/// attachment ID and caches the verified file — decides what is a download and what is a cache
/// hit. The page only decides what to decode and when to let go of it.
private struct MediaAttachmentViewerPage: View {
  @Environment(\.privateMediaPreviewLoader) private var previewLoader
  @State private var model: PrivateMediaPreviewModel
  /// Viewer-resolution decode of the original, held only while this page is the one on screen.
  ///
  /// `model.image` stays at preview resolution so a neighbouring page costs a few megabytes and
  /// shows something the instant it slides in; the sharp copy is re-decoded for the current page
  /// and dropped on the way out. Holding 4,096px decodes for a full group of four would be roughly
  /// 200 MB of bitmaps for photos the user is not looking at.
  @State private var viewerImage: UIImage?

  let descriptor: MediaAttachmentDescriptor
  let isCurrent: Bool
  let onAuthenticationRequired: @MainActor () -> Void
  /// Reports the verified file, and reports `nil` when the page lets go of it. The shell's save
  /// affordance is spelled from this, so a path that outlived its lease would offer to write a
  /// file the cache may already have evicted.
  let onFileResolved: @MainActor (URL?) -> Void

  @MainActor
  init(
    descriptor: MediaAttachmentDescriptor,
    isCurrent: Bool,
    onAuthenticationRequired: @escaping @MainActor () -> Void,
    onFileResolved: @escaping @MainActor (URL?) -> Void
  ) {
    self.descriptor = descriptor
    self.isCurrent = isCurrent
    self.onAuthenticationRequired = onAuthenticationRequired
    self.onFileResolved = onFileResolved
    _model = State(
      initialValue: PrivateMediaPreviewModel(
        descriptor: PrivateMediaPreviewDescriptor(
          attachmentID: descriptor.id,
          fileName: descriptor.fileName,
          contentType: descriptor.contentType,
          byteSize: descriptor.byteSize
        )
      )
    )
  }

  var body: some View {
    ZStack {
      WoorisaiColor.Bg.immersive.ignoresSafeArea()
      content
    }
    .task(id: isCurrent) {
      // Images load on sight so a swipe lands on a picture rather than a spinner. Video keeps the
      // rule the feed already follows — up to 100 MB is only fetched once the user is looking at
      // it, and inside the viewer that means becoming the current page.
      guard model.state == .idle, descriptor.isImage || isCurrent else { return }
      model.load(using: previewLoader, decodeMaxPixelSize: MediaImagePreview.maximumPixelSize)
    }
    .task(id: ViewerDecodeKey(isCurrent: isCurrent, localURL: model.localURL)) {
      guard descriptor.isImage else { return }
      guard isCurrent, let localURL = model.localURL else {
        viewerImage = nil
        return
      }
      guard viewerImage == nil else { return }
      // 4,096px covers a 3x screen at the viewer's maximum zoom while still bounding decoded
      // memory for oversized originals.
      viewerImage = await Task.detached(priority: .userInitiated) {
        MediaImagePreview.thumbnail(fromFileAt: localURL, maximumPixelSize: 4_096)
      }.value
    }
    .onChange(of: model.localURL, initial: true) { _, localURL in
      onFileResolved(localURL)
    }
    .onChange(of: model.state) { _, state in
      guard state == .authenticationRequired else { return }
      onAuthenticationRequired()
    }
    .onDisappear {
      viewerImage = nil
      model.clear()
      onFileResolved(nil)
    }
  }

  @ViewBuilder
  private var content: some View {
    if descriptor.isImage {
      if let image = viewerImage ?? model.image {
        MediaAspectFitImageSurface(
          image: image,
          accessibilityName: "첨부 사진 \(descriptor.fileName) 전체 보기"
        )
        .padding(.vertical, WoorisaiSpacing.xLarge)
        .accessibilityIdentifier("media.viewer")
      } else {
        statusSurface
      }
    } else if let localURL = model.localURL {
      PrivateVideoViewer(
        url: localURL,
        fileName: descriptor.fileName,
        isCurrent: isCurrent,
        onRetry: {
          model.reloadDiscardingCurrentLease(
            using: previewLoader,
            decodeMaxPixelSize: MediaImagePreview.maximumPixelSize
          )
        }
      )
    } else {
      statusSurface
    }
  }

  private var statusSurface: some View {
    VStack(spacing: WoorisaiSpacing.medium) {
      if let failureMessage {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.largeTitle)
          .foregroundStyle(WoorisaiColor.Fg.staticWhite)

        Text(failureMessage)
          .font(.subheadline)
          .foregroundStyle(WoorisaiColor.Fg.staticWhiteMuted)
          .multilineTextAlignment(.center)

        Button {
          model.load(using: previewLoader, decodeMaxPixelSize: MediaImagePreview.maximumPixelSize)
        } label: {
          Label("다시 시도", systemImage: "arrow.clockwise")
            .font(.subheadline.weight(.bold))
            .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
            .padding(.horizontal, WoorisaiSpacing.regular)
        }
        .buttonStyle(.borderedProminent)
        .tint(WoorisaiColor.Bg.brandSolid)
        .foregroundStyle(WoorisaiColor.Fg.staticWhite)
        .accessibilityIdentifier("media.viewer.retry")
      } else {
        ProgressView()
          .tint(WoorisaiColor.Fg.staticWhite)

        Text(descriptor.isImage ? "사진을 불러오는 중" : "동영상을 준비하는 중")
          .font(.subheadline)
          .foregroundStyle(WoorisaiColor.Fg.staticWhiteMuted)
      }
    }
    .padding(WoorisaiSpacing.xLarge)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("media.viewer.status")
  }

  private var failureMessage: String? {
    switch model.state {
    case .authenticationRequired: "다시 로그인이 필요해요."
    case .notFound: "첨부 파일을 찾을 수 없어요."
    case .unavailable: "첨부 파일을 잠시 열 수 없어요."
    case .invalidContent: "첨부 파일이 손상되었거나 정보가 일치하지 않아요."
    case .failed: "첨부 파일을 열지 못했어요."
    case .idle, .loading, .loaded: nil
    }
  }
}

/// `task(id:)` needs one `Equatable` value, and the decode depends on both being the page in view
/// and having a verified file to read.
private struct ViewerDecodeKey: Equatable {
  let isCurrent: Bool
  let localURL: URL?
}
