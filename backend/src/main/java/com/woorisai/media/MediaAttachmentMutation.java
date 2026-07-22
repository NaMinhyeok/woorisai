package com.woorisai.media;

public interface MediaAttachmentMutation {

    void attachScoreChange(AttachScoreChangeMediaCommand command);

    void attachScoreComment(AttachScoreCommentMediaCommand command);

    void replaceDiaryEntry(ReplaceDiaryEntryMediaCommand command);

    final class InvalidMediaAttachmentRequestException extends RuntimeException {

        public InvalidMediaAttachmentRequestException() {
            super("Media attachment request is invalid");
        }
    }

    final class MediaUploadNotFoundException extends RuntimeException {

        public MediaUploadNotFoundException() {
            super("Media upload was not found");
        }
    }

    final class MediaAttachmentForbiddenException extends RuntimeException {

        public MediaAttachmentForbiddenException() {
            super("Media upload cannot be attached by this participant");
        }
    }

    final class MediaAttachmentConflictException extends RuntimeException {

        public MediaAttachmentConflictException() {
            super("Media upload cannot be attached in its current state");
        }
    }

    final class MediaAttachmentUnavailableException extends RuntimeException {

        public MediaAttachmentUnavailableException() {
            super("Media attachment mutation is not available");
        }

        public MediaAttachmentUnavailableException(Throwable cause) {
            super("Media attachment mutation is not available", cause);
        }
    }
}
