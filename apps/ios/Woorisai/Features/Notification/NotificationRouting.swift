import Foundation

enum NotificationResourceRefetchIntent: Equatable, Hashable, Sendable {
  case scoreChange(id: Int64)
  case diaryEntry(id: Int64)
}

enum NotificationNavigationDisposition: Equatable, Sendable {
  case navigate
  case refetchVisible

  static func resolve(currentPath: [Int64], targetID: Int64) -> Self {
    currentPath == [targetID] ? .refetchVisible : .navigate
  }
}

enum NotificationPayloadRouter {
  /// Converts only the server-owned routing fields into a resource refetch. Alert text and all
  /// other payload values are deliberately ignored and never become app state.
  static func refetchIntent(
    eventType: String?,
    resourceID: String?
  ) -> NotificationResourceRefetchIntent? {
    guard let eventType,
      let resourceID,
      !resourceID.isEmpty,
      resourceID.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
      let id = Int64(resourceID),
      id > 0
    else {
      return nil
    }

    switch eventType {
    case "relationshipScoreChanged", "scoreChangeCommentCreated":
      return .scoreChange(id: id)
    case "diaryEntryCommentCreated":
      return .diaryEntry(id: id)
    default:
      return nil
    }
  }
}
