package com.woorisai.media.internal;

final class InvalidMediaUploadRequestException extends RuntimeException {
    InvalidMediaUploadRequestException() {
        super("Media upload request is invalid");
    }
}

final class MediaUploadInitiationUnavailableException extends RuntimeException {
    MediaUploadInitiationUnavailableException() {
        super("Media upload initiation is not available");
    }

    MediaUploadInitiationUnavailableException(Throwable cause) {
        super("Media upload initiation is not available", cause);
    }
}

final class InvalidMediaUploadCompletionRequestException extends RuntimeException {
    InvalidMediaUploadCompletionRequestException() {
        super("Media upload completion request is invalid");
    }
}

final class MediaUploadNotFoundException extends RuntimeException {
    MediaUploadNotFoundException() {
        super("Media upload was not found");
    }
}

final class MediaUploadCompletionForbiddenException extends RuntimeException {
    MediaUploadCompletionForbiddenException() {
        super("Media upload completion is forbidden");
    }
}

final class MediaUploadCompletionConflictException extends RuntimeException {
    MediaUploadCompletionConflictException() {
        super("Media upload cannot be completed in its current state");
    }
}

final class MediaUploadContentRejectedException extends RuntimeException {
    MediaUploadContentRejectedException() {
        super("Uploaded media content was rejected");
    }
}

final class MediaUploadCompletionUnavailableException extends RuntimeException {
    MediaUploadCompletionUnavailableException() {
        super("Media upload completion is not available");
    }

    MediaUploadCompletionUnavailableException(Throwable cause) {
        super("Media upload completion is not available", cause);
    }
}

final class InvalidMediaUploadDiscardRequestException extends RuntimeException {
    InvalidMediaUploadDiscardRequestException() {
        super("Media upload discard request is invalid");
    }
}

final class MediaUploadDiscardForbiddenException extends RuntimeException {
    MediaUploadDiscardForbiddenException() {
        super("Media upload discard is forbidden");
    }
}

final class MediaUploadDiscardConflictException extends RuntimeException {
    MediaUploadDiscardConflictException() {
        super("Media upload cannot be discarded in its current state");
    }
}

final class MediaUploadDiscardUnavailableException extends RuntimeException {
    MediaUploadDiscardUnavailableException() {
        super("Media upload discard is not available");
    }

    MediaUploadDiscardUnavailableException(Throwable cause) {
        super("Media upload discard is not available", cause);
    }
}

final class InvalidMediaDownloadRequestException extends RuntimeException {
    InvalidMediaDownloadRequestException() {
        super("Media download request is invalid");
    }
}

final class MediaAttachmentNotFoundException extends RuntimeException {
    MediaAttachmentNotFoundException() {
        super("Media attachment was not found");
    }
}

final class MediaDownloadUnavailableException extends RuntimeException {
    MediaDownloadUnavailableException() {
        super("Media download is not available");
    }

    MediaDownloadUnavailableException(Throwable cause) {
        super("Media download is not available", cause);
    }
}
