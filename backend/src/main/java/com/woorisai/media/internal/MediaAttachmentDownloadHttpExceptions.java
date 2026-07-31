package com.woorisai.media.internal;

import com.woorisai.support.error.ApplicationException;
import java.util.UUID;
import java.util.regex.Pattern;

final class InvalidMediaAttachmentDownloadRequestException extends ApplicationException {

    InvalidMediaAttachmentDownloadRequestException() {
        super(MediaError.INVALID_DOWNLOAD_REQUEST, "Media attachment download request is invalid");
    }
}

final class MediaAttachmentDownloadUnavailableException extends ApplicationException {

    MediaAttachmentDownloadUnavailableException() {
        super(MediaError.DOWNLOAD_UNAVAILABLE, "Media attachment download is not available");
    }
}

final class MediaAttachmentDownloadHttpIds {

    private static final Pattern CANONICAL_UUID = Pattern.compile(
            "(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");

    private MediaAttachmentDownloadHttpIds() {}

    static long requireActor(Long actorId) {
        if (actorId == null || actorId <= 0) {
            throw new InvalidMediaAttachmentDownloadRequestException();
        }
        return actorId;
    }

    static UUID parse(String value) {
        if (value == null || !CANONICAL_UUID.matcher(value).matches()) {
            throw new InvalidMediaAttachmentDownloadRequestException();
        }
        try {
            return UUID.fromString(value);
        } catch (IllegalArgumentException exception) {
            throw new InvalidMediaAttachmentDownloadRequestException();
        }
    }
}
