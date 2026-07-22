package com.woorisai.media.internal;

import com.woorisai.media.MediaKind;
import java.util.Locale;
import java.util.Set;

final class MediaPolicy {

    static final long MEBIBYTE = 1024L * 1024L;
    static final long MAX_IMAGE_SIZE = 10 * MEBIBYTE;
    static final long MAX_VIDEO_SIZE = 100 * MEBIBYTE;
    static final String PRIVATE_CACHE_CONTROL = "private, no-store, max-age=0";

    private static final Set<String> IMAGE_CONTENT_TYPES =
            Set.of("image/jpeg", "image/png", "image/webp");
    private static final Set<String> VIDEO_CONTENT_TYPES =
            Set.of("video/mp4", "video/webm", "video/quicktime");

    private final int uploadUrlTtlSeconds;

    MediaPolicy(int uploadUrlTtlSeconds) {
        this.uploadUrlTtlSeconds = MediaUrlTtl.requireSeconds(
                uploadUrlTtlSeconds,
                () -> new IllegalArgumentException("Media upload URL TTL is invalid"));
    }

    ValidatedMediaUpload validate(
            long uploaderId,
            MediaPurpose purpose,
            MediaKind kind,
            String fileName,
            String requestedContentType,
            long byteSize) {
        if (uploaderId <= 0 || purpose == null || kind == null) {
            throw new InvalidMediaUploadRequestException();
        }

        String originalName = normalizeOriginalName(fileName);
        String contentType = normalizeContentType(requestedContentType);
        validateContent(purpose, kind, contentType, byteSize);
        return new ValidatedMediaUpload(
                uploaderId,
                purpose,
                kind,
                originalName,
                contentType,
                byteSize);
    }

    int uploadUrlTtlSeconds() {
        return uploadUrlTtlSeconds;
    }

    private static String normalizeOriginalName(String value) {
        if (value == null) {
            throw new InvalidMediaUploadRequestException();
        }
        String normalized = value.strip().replace('\\', '/');
        int lastSeparator = normalized.lastIndexOf('/');
        if (lastSeparator >= 0) {
            normalized = normalized.substring(lastSeparator + 1);
        }
        if (normalized.isEmpty()
                || normalized.codePointCount(0, normalized.length()) > 255
                || normalized.codePoints().anyMatch(Character::isISOControl)) {
            throw new InvalidMediaUploadRequestException();
        }
        return normalized;
    }

    private static String normalizeContentType(String value) {
        if (value == null) {
            throw new InvalidMediaUploadRequestException();
        }
        int parameterStart = value.indexOf(';');
        String normalized = (parameterStart < 0 ? value : value.substring(0, parameterStart))
                .strip()
                .toLowerCase(Locale.ROOT);
        if (normalized.isEmpty() || normalized.length() > 100) {
            throw new InvalidMediaUploadRequestException();
        }
        return normalized;
    }

    private static void validateContent(
            MediaPurpose purpose,
            MediaKind kind,
            String contentType,
            long expectedSize) {
        if (expectedSize <= 0) {
            throw new InvalidMediaUploadRequestException();
        }
        if (kind == MediaKind.IMAGE) {
            if (!IMAGE_CONTENT_TYPES.contains(contentType) || expectedSize > MAX_IMAGE_SIZE) {
                throw new InvalidMediaUploadRequestException();
            }
            return;
        }
        if (purpose == MediaPurpose.SCORE_CHANGE
                || !VIDEO_CONTENT_TYPES.contains(contentType)
                || expectedSize > MAX_VIDEO_SIZE) {
            throw new InvalidMediaUploadRequestException();
        }
    }
}

record ValidatedMediaUpload(
        long uploaderId,
        MediaPurpose purpose,
        MediaKind kind,
        String originalName,
        String contentType,
        long expectedSize) {}
