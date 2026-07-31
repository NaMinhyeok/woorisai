package com.woorisai.support.error;

import static org.assertj.core.api.Assertions.assertThat;

import java.lang.reflect.InvocationTargetException;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

/**
 * Pins the published failure contract.
 *
 * <p>Every value here is copied from {@code contracts/openapi-v2.yaml} and the HTTP tests. This
 * test is the reason the error-handling refactor cannot silently change a response: a renamed code,
 * a reworded title or a dropped constant fails here before it reaches the wire.
 */
class ErrorCatalogTest {

    private record Contract(HttpStatus status, String title, String detail, boolean exposesInstance) {

        static Contract of(HttpStatus status, String title, String detail) {
            return new Contract(status, title, detail, true);
        }

        static Contract withoutInstance(HttpStatus status, String title, String detail) {
            return new Contract(status, title, detail, false);
        }
    }

    /** errorCode to its exact published response. Do not reword these strings. */
    private static final Map<String, Contract> PUBLISHED = Map.ofEntries(
            Map.entry("UNSUPPORTED_MEDIA_TYPE", Contract.of(
                    HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                    "Unsupported media type",
                    "Content-Type must be application/json.")),
            Map.entry("INVALID_DIARY_REQUEST", Contract.of(
                    HttpStatus.BAD_REQUEST,
                    "Invalid diary request",
                    "The diary request is invalid.")),
            Map.entry("DIARY_NOT_FOUND", Contract.of(
                    HttpStatus.NOT_FOUND,
                    "Diary resource not found",
                    "The requested diary resource was not found.")),
            Map.entry("DIARY_FORBIDDEN", Contract.of(
                    HttpStatus.FORBIDDEN,
                    "Diary mutation forbidden",
                    "Only the author can change this diary resource.")),
            Map.entry("DIARY_CONFLICT", Contract.of(
                    HttpStatus.CONFLICT,
                    "Diary conflict",
                    "The diary request conflicts with current state.")),
            Map.entry("DIARY_UNAVAILABLE", Contract.of(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Diary unavailable",
                    "Diary data is temporarily unavailable.")),
            Map.entry("INVALID_RELATIONSHIP_REQUEST", Contract.of(
                    HttpStatus.BAD_REQUEST,
                    "Invalid relationship request",
                    "The relationship request is invalid.")),
            Map.entry("RELATIONSHIP_NOT_FOUND", Contract.of(
                    HttpStatus.NOT_FOUND,
                    "Relationship resource not found",
                    "The requested relationship resource was not found.")),
            Map.entry("RELATIONSHIP_FORBIDDEN", Contract.of(
                    HttpStatus.FORBIDDEN,
                    "Relationship access denied",
                    "Access to this relationship resource is denied.")),
            Map.entry("RELATIONSHIP_CONFLICT", Contract.of(
                    HttpStatus.CONFLICT,
                    "Relationship conflict",
                    "The relationship request conflicts with current state.")),
            Map.entry("RELATIONSHIP_UNAVAILABLE", Contract.of(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Relationship unavailable",
                    "Relationship data is temporarily unavailable.")),
            Map.entry("LOGIN_OPTIONS_UNAVAILABLE", Contract.of(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Login options unavailable",
                    "The participant login options are temporarily unavailable.")),
            Map.entry("INVALID_MEDIA_UPLOAD_REQUEST", Contract.of(
                    HttpStatus.BAD_REQUEST,
                    "Invalid media upload request",
                    "The media upload request is invalid.")),
            Map.entry("MEDIA_UPLOAD_FORBIDDEN", Contract.of(
                    HttpStatus.FORBIDDEN,
                    "Media upload forbidden",
                    "The media upload is not owned by the authenticated participant.")),
            Map.entry("MEDIA_UPLOAD_NOT_FOUND", Contract.of(
                    HttpStatus.NOT_FOUND,
                    "Media upload not found",
                    "The media upload or authorized parent was not found.")),
            Map.entry("MEDIA_UPLOAD_CONFLICT", Contract.of(
                    HttpStatus.CONFLICT,
                    "Media upload conflict",
                    "The media upload cannot be processed in its current state.")),
            Map.entry("MEDIA_UPLOADS_UNAVAILABLE", Contract.of(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Media uploads unavailable",
                    "Media uploads are temporarily unavailable.")),
            Map.entry("INVALID_MEDIA_DOWNLOAD_REQUEST", Contract.of(
                    HttpStatus.BAD_REQUEST,
                    "Invalid media download request",
                    "The media download request is invalid.")),
            Map.entry("MEDIA_ATTACHMENT_NOT_FOUND", Contract.of(
                    HttpStatus.NOT_FOUND,
                    "Media attachment not found",
                    "The media attachment was not found.")),
            Map.entry("MEDIA_DOWNLOAD_UNAVAILABLE", Contract.of(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Media download unavailable",
                    "Media download is temporarily unavailable.")),
            Map.entry("INVALID_NOTIFICATION_FID", Contract.withoutInstance(
                    HttpStatus.BAD_REQUEST,
                    "Invalid notification FID request",
                    "Request must contain one valid Firebase installation ID.")),
            Map.entry("NOTIFICATION_FID_UNAVAILABLE", Contract.withoutInstance(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Notification FID service unavailable",
                    "Notification FID service is temporarily unavailable.")),
            Map.entry("AUTHENTICATION_REQUIRED", Contract.of(
                    HttpStatus.UNAUTHORIZED,
                    "Authentication required",
                    "Valid HTTP Basic participant credentials are required.")),
            Map.entry("ACCESS_DENIED", Contract.of(
                    HttpStatus.FORBIDDEN,
                    "Access denied",
                    "Access to this resource is denied.")),
            Map.entry("AUTHENTICATION_UNAVAILABLE", Contract.of(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Authentication unavailable",
                    "Authentication is temporarily unavailable.")));

    private static final List<String> CATALOG_TYPES = List.of(
            "support.error.CommonError",
            "diary.internal.DiaryError",
            "relationship.internal.RelationshipError",
            "media.internal.MediaError",
            "notification.internal.NotificationError",
            "identity.internal.IdentityError");

    @Test
    @DisplayName("errorCode는 중복되지 않는다")
    void errorCodesAreUnique() {
        assertThat(descriptors().map(ErrorDescriptor::code).toList()).doesNotHaveDuplicates();
    }

    @Test
    @DisplayName("errorCode 집합은 공개 계약과 정확히 일치한다")
    void errorCodesMatchPublishedContract() {
        assertThat(descriptors().map(ErrorDescriptor::code))
                .containsExactlyInAnyOrderElementsOf(PUBLISHED.keySet());
    }

    @Test
    @DisplayName("각 errorCode의 status, title, detail은 공개 계약과 문자 단위로 일치한다")
    void responseFieldsMatchPublishedContract() {
        descriptors().forEach(error -> {
            Contract expected = PUBLISHED.get(error.code());
            assertThat(expected)
                    .withFailMessage("errorCode %s is not part of the published contract", error.code())
                    .isNotNull();
            assertThat(error.status()).as("status of %s", error.code()).isEqualTo(expected.status());
            assertThat(error.title()).as("title of %s", error.code()).isEqualTo(expected.title());
            assertThat(error.detail()).as("detail of %s", error.code()).isEqualTo(expected.detail());
        });
    }

    @Test
    @DisplayName("notification 오류만 instance를 노출하지 않는다")
    void onlyNotificationFailuresOmitInstance() {
        descriptors().forEach(error -> assertThat(error.exposesInstance())
                .as("exposesInstance of %s", error.code())
                .isEqualTo(PUBLISHED.get(error.code()).exposesInstance()));
    }

    @Test
    @DisplayName("모든 오류는 로그 수준을 선언한다")
    void everyFailureDeclaresLogLevel() {
        descriptors().forEach(error -> assertThat(error.logLevel())
                .as("logLevel of %s", error.code())
                .isNotNull());
    }

    private Stream<ErrorDescriptor> descriptors() {
        return CATALOG_TYPES.stream().flatMap(this::constantsOf);
    }

    @SuppressWarnings("unchecked")
    private Stream<ErrorDescriptor> constantsOf(String packageSuffix) {
        Class<? extends ErrorDescriptor> type;
        try {
            type = (Class<? extends ErrorDescriptor>) Class.forName("com.woorisai." + packageSuffix);
        } catch (ClassNotFoundException exception) {
            throw new IllegalStateException(exception);
        }
        try {
            var values = type.getDeclaredMethod("values");
            values.setAccessible(true);
            return Arrays.stream((ErrorDescriptor[]) values.invoke(null));
        } catch (NoSuchMethodException | IllegalAccessException exception) {
            throw new IllegalStateException(exception);
        } catch (InvocationTargetException exception) {
            throw new IllegalStateException(exception.getCause());
        }
    }
}
