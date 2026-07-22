import Testing

@testable import WoorisaiAPI

struct WoorisaiAPIErrorTests {
  @Test(arguments: ProblemExample.all)
  func mapsDocumentedProblemToAppOwnedError(example: ProblemExample) {
    #expect(
      WoorisaiAPIError.mapProblem(
        httpStatus: example.status,
        problemStatus: Int32(example.status),
        errorCode: example.errorCode
      ) == example.expected
    )
  }

  @Test
  func rejectsProblemWhoseBodyStatusDoesNotMatchHTTPStatus() {
    #expect(
      WoorisaiAPIError.mapProblem(
        httpStatus: 401,
        problemStatus: 503,
        errorCode: "AUTHENTICATION_REQUIRED"
      ) == .schemaDrift
    )
  }

  @Test
  func rejectsUnknownProblemCodeRatherThanGuessingFromStatus() {
    #expect(
      WoorisaiAPIError.mapProblem(
        httpStatus: 409,
        problemStatus: 409,
        errorCode: "UNKNOWN_CONFLICT"
      ) == .schemaDrift
    )
  }
}

struct ProblemExample: Sendable, CustomTestStringConvertible {
  let status: Int
  let errorCode: String
  let expected: WoorisaiAPIError

  var testDescription: String { "\(status) \(errorCode)" }

  static let all: [ProblemExample] = [
    .init(status: 400, errorCode: "INVALID_MEDIA_UPLOAD_REQUEST", expected: .invalidRequest),
    .init(status: 400, errorCode: "INVALID_MEDIA_DOWNLOAD_REQUEST", expected: .invalidRequest),
    .init(status: 400, errorCode: "INVALID_RELATIONSHIP_REQUEST", expected: .invalidRequest),
    .init(status: 400, errorCode: "INVALID_DIARY_REQUEST", expected: .invalidRequest),
    .init(status: 400, errorCode: "INVALID_NOTIFICATION_FID", expected: .invalidRequest),
    .init(status: 401, errorCode: "AUTHENTICATION_REQUIRED", expected: .credentialRejected),
    .init(status: 403, errorCode: "MEDIA_UPLOAD_FORBIDDEN", expected: .forbidden),
    .init(status: 403, errorCode: "RELATIONSHIP_FORBIDDEN", expected: .forbidden),
    .init(status: 403, errorCode: "DIARY_FORBIDDEN", expected: .forbidden),
    .init(status: 404, errorCode: "MEDIA_UPLOAD_NOT_FOUND", expected: .notFound),
    .init(status: 404, errorCode: "MEDIA_ATTACHMENT_NOT_FOUND", expected: .notFound),
    .init(status: 404, errorCode: "RELATIONSHIP_NOT_FOUND", expected: .notFound),
    .init(status: 404, errorCode: "DIARY_NOT_FOUND", expected: .notFound),
    .init(status: 409, errorCode: "MEDIA_UPLOAD_CONFLICT", expected: .conflict),
    .init(status: 409, errorCode: "RELATIONSHIP_CONFLICT", expected: .conflict),
    .init(status: 409, errorCode: "DIARY_CONFLICT", expected: .conflict),
    .init(status: 415, errorCode: "UNSUPPORTED_MEDIA_TYPE", expected: .unsupportedMediaType),
    .init(status: 503, errorCode: "LOGIN_OPTIONS_UNAVAILABLE", expected: .loginOptionsUnavailable),
    .init(status: 503, errorCode: "AUTHENTICATION_UNAVAILABLE", expected: .serviceUnavailable),
    .init(status: 503, errorCode: "MEDIA_UPLOADS_UNAVAILABLE", expected: .serviceUnavailable),
    .init(status: 503, errorCode: "MEDIA_DOWNLOAD_UNAVAILABLE", expected: .serviceUnavailable),
    .init(status: 503, errorCode: "RELATIONSHIP_UNAVAILABLE", expected: .serviceUnavailable),
    .init(status: 503, errorCode: "DIARY_UNAVAILABLE", expected: .serviceUnavailable),
    .init(status: 503, errorCode: "NOTIFICATION_FID_UNAVAILABLE", expected: .serviceUnavailable),
  ]
}
