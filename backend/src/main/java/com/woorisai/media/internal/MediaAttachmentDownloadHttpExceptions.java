package com.woorisai.media.internal;

import com.woorisai.support.error.ApplicationException;
import java.util.UUID;

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

    private MediaAttachmentDownloadHttpIds() {}

    static long requireActor(Long actorId) {
        return MediaHttpIds.requireActor(
                actorId, InvalidMediaAttachmentDownloadRequestException::new);
    }

    static UUID parse(String value) {
        return MediaHttpIds.parse(value, InvalidMediaAttachmentDownloadRequestException::new);
    }
}
