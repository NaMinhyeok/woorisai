package com.woorisai.media.internal;

import com.woorisai.support.error.ApplicationException;
import java.util.UUID;

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
        return MediaHttpIds.requireActor(actorId, InvalidMediaUploadHttpRequestException::new);
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

    private MediaUploadHttpIds() {}

    static UUID parse(String value) {
        return MediaHttpIds.parse(value, InvalidMediaUploadHttpRequestException::new);
    }
}
