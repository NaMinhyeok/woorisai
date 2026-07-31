package com.woorisai.media.internal;

import com.woorisai.support.error.ApplicationException;

final class InvalidMediaUploadRequestException extends ApplicationException {
    InvalidMediaUploadRequestException() {
        super(MediaError.INVALID_UPLOAD_REQUEST, "Media upload request is invalid");
    }
}

final class MediaUploadInitiationUnavailableException extends ApplicationException {
    MediaUploadInitiationUnavailableException() {
        super(MediaError.UPLOADS_UNAVAILABLE, "Media upload initiation is not available");
    }

    MediaUploadInitiationUnavailableException(Throwable cause) {
        super(MediaError.UPLOADS_UNAVAILABLE, "Media upload initiation is not available", cause);
    }
}

final class InvalidMediaUploadCompletionRequestException extends ApplicationException {
    InvalidMediaUploadCompletionRequestException() {
        super(MediaError.INVALID_UPLOAD_REQUEST, "Media upload completion request is invalid");
    }
}

final class MediaUploadNotFoundException extends ApplicationException {
    MediaUploadNotFoundException() {
        super(MediaError.UPLOAD_NOT_FOUND, "Media upload was not found");
    }
}

final class MediaUploadCompletionForbiddenException extends ApplicationException {
    MediaUploadCompletionForbiddenException() {
        super(MediaError.UPLOAD_FORBIDDEN, "Media upload completion is forbidden");
    }
}

final class MediaUploadCompletionConflictException extends ApplicationException {
    MediaUploadCompletionConflictException() {
        super(MediaError.UPLOAD_CONFLICT, "Media upload cannot be completed in its current state");
    }
}

final class MediaUploadContentRejectedException extends ApplicationException {
    MediaUploadContentRejectedException() {
        super(MediaError.INVALID_UPLOAD_REQUEST, "Uploaded media content was rejected");
    }
}

final class MediaUploadCompletionUnavailableException extends ApplicationException {
    MediaUploadCompletionUnavailableException() {
        super(MediaError.UPLOADS_UNAVAILABLE, "Media upload completion is not available");
    }

    MediaUploadCompletionUnavailableException(Throwable cause) {
        super(MediaError.UPLOADS_UNAVAILABLE, "Media upload completion is not available", cause);
    }
}

final class InvalidMediaUploadDiscardRequestException extends ApplicationException {
    InvalidMediaUploadDiscardRequestException() {
        super(MediaError.INVALID_UPLOAD_REQUEST, "Media upload discard request is invalid");
    }
}

final class MediaUploadDiscardForbiddenException extends ApplicationException {
    MediaUploadDiscardForbiddenException() {
        super(MediaError.UPLOAD_FORBIDDEN, "Media upload discard is forbidden");
    }
}

final class MediaUploadDiscardConflictException extends ApplicationException {
    MediaUploadDiscardConflictException() {
        super(MediaError.UPLOAD_CONFLICT, "Media upload cannot be discarded in its current state");
    }
}

final class MediaUploadDiscardUnavailableException extends ApplicationException {
    MediaUploadDiscardUnavailableException() {
        super(MediaError.UPLOADS_UNAVAILABLE, "Media upload discard is not available");
    }

    MediaUploadDiscardUnavailableException(Throwable cause) {
        super(MediaError.UPLOADS_UNAVAILABLE, "Media upload discard is not available", cause);
    }
}

final class InvalidMediaDownloadRequestException extends ApplicationException {
    InvalidMediaDownloadRequestException() {
        super(MediaError.INVALID_DOWNLOAD_REQUEST, "Media download request is invalid");
    }
}

final class MediaAttachmentNotFoundException extends ApplicationException {
    MediaAttachmentNotFoundException() {
        super(MediaError.ATTACHMENT_NOT_FOUND, "Media attachment was not found");
    }
}

final class MediaDownloadUnavailableException extends ApplicationException {
    MediaDownloadUnavailableException() {
        super(MediaError.DOWNLOAD_UNAVAILABLE, "Media download is not available");
    }

    MediaDownloadUnavailableException(Throwable cause) {
        super(MediaError.DOWNLOAD_UNAVAILABLE, "Media download is not available", cause);
    }
}
