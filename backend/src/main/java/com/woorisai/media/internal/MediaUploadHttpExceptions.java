package com.woorisai.media.internal;

import com.woorisai.support.error.ApplicationException;
import java.util.UUID;
import java.util.regex.Pattern;

final class InvalidMediaUploadHttpRequestException extends ApplicationException {

    InvalidMediaUploadHttpRequestException() {
        super(MediaError.INVALID_UPLOAD_REQUEST, "Media upload HTTP request is invalid");
    }
}

final class MediaUploadsUnavailableHttpException extends ApplicationException {

    MediaUploadsUnavailableHttpException() {
        super(MediaError.UPLOADS_UNAVAILABLE, "Media uploads are not available");
    }
}

final class MediaHttpActors {

    private MediaHttpActors() {}

    static long require(Long actorId) {
        if (actorId == null || actorId <= 0) {
            throw new InvalidMediaUploadHttpRequestException();
        }
        return actorId;
    }
}

final class MediaUploadHttpBodies {

    private MediaUploadHttpBodies() {}

    static void requireEmpty(byte[] body) {
        if (body != null && body.length > 0) {
            throw new InvalidMediaUploadHttpRequestException();
        }
    }
}

final class MediaUploadHttpIds {

    private static final Pattern CANONICAL_UUID = Pattern.compile(
            "(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");

    private MediaUploadHttpIds() {}

    static UUID parse(String value) {
        if (value == null || !CANONICAL_UUID.matcher(value).matches()) {
            throw new InvalidMediaUploadHttpRequestException();
        }
        try {
            return UUID.fromString(value);
        } catch (IllegalArgumentException exception) {
            throw new InvalidMediaUploadHttpRequestException();
        }
    }
}
