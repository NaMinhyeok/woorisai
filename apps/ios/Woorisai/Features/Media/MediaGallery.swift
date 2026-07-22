import SwiftUI
import UIKit
import WoorisaiAPI

enum MediaInlineTileFormat: Equatable, Sendable {
  case singleImage
  case mosaicImage
  case video

  var aspectRatio: CGFloat {
    switch self {
    case .singleImage:
      4 / 3
    case .mosaicImage:
      1
    case .video:
      16 / 9
    }
  }
}

enum MediaGroupLayout: Equatable, Sendable {
  case empty
  case singleImage
  case imageMosaic(columns: Int)
  case video

  static func resolve(kinds: [MediaKind]) -> Self {
    guard !kinds.isEmpty else { return .empty }
    if kinds.contains(.video) { return .video }
    if kinds.count == 1 { return .singleImage }
    return .imageMosaic(columns: kinds.count == 3 ? 3 : 2)
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
    case .imageMosaic(let columnCount):
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: WoorisaiControlMetric.mediaGap),
          count: dynamicTypeSize.isAccessibilitySize ? min(columnCount, 2) : columnCount
        ),
        spacing: WoorisaiControlMetric.mediaGap
      ) {
        ForEach(items) { item in
          tile(item, .mosaicImage)
            .aspectRatio(MediaInlineTileFormat.mosaicImage.aspectRatio, contentMode: .fit)
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

struct MediaTileSurface<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(WoorisaiPalette.creamDeep)
      .clipShape(RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
          .stroke(WoorisaiPalette.line, lineWidth: 1)
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
