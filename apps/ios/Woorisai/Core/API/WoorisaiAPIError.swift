import Foundation

public enum WoorisaiAPIError: Error, Equatable, Sendable {
  case credentialMissing
  case credentialRejected
  case invalidRequest
  case forbidden
  case notFound
  case conflict
  case unsupportedMediaType
  case loginOptionsUnavailable
  case serviceUnavailable
  case untrustedOrigin
  case schemaDrift
  case undocumentedResponse(statusCode: Int)
  case transport
}

extension WoorisaiAPIError {
  static func mapProblem(
    httpStatus: Int,
    problemStatus: Int32,
    errorCode: String
  ) -> WoorisaiAPIError {
    guard Int(problemStatus) == httpStatus else {
      return .schemaDrift
    }

    switch (httpStatus, errorCode) {
    case (400, "INVALID_MEDIA_UPLOAD_REQUEST"),
      (400, "INVALID_MEDIA_DOWNLOAD_REQUEST"),
      (400, "INVALID_RELATIONSHIP_REQUEST"),
      (400, "INVALID_DIARY_REQUEST"),
      (400, "INVALID_NOTIFICATION_FID"):
      return .invalidRequest
    case (401, "AUTHENTICATION_REQUIRED"):
      return .credentialRejected
    case (403, "MEDIA_UPLOAD_FORBIDDEN"),
      (403, "RELATIONSHIP_FORBIDDEN"),
      (403, "DIARY_FORBIDDEN"):
      return .forbidden
    case (404, "MEDIA_UPLOAD_NOT_FOUND"),
      (404, "MEDIA_ATTACHMENT_NOT_FOUND"),
      (404, "RELATIONSHIP_NOT_FOUND"),
      (404, "DIARY_NOT_FOUND"):
      return .notFound
    case (409, "MEDIA_UPLOAD_CONFLICT"),
      (409, "RELATIONSHIP_CONFLICT"),
      (409, "DIARY_CONFLICT"):
      return .conflict
    case (415, "UNSUPPORTED_MEDIA_TYPE"):
      return .unsupportedMediaType
    case (503, "LOGIN_OPTIONS_UNAVAILABLE"):
      return .loginOptionsUnavailable
    case (503, "AUTHENTICATION_UNAVAILABLE"),
      (503, "MEDIA_UPLOADS_UNAVAILABLE"),
      (503, "MEDIA_DOWNLOAD_UNAVAILABLE"),
      (503, "RELATIONSHIP_UNAVAILABLE"),
      (503, "DIARY_UNAVAILABLE"),
      (503, "NOTIFICATION_FID_UNAVAILABLE"):
      return .serviceUnavailable
    default:
      return .schemaDrift
    }
  }
}
