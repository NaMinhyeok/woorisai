package com.woorisai.diary.internal;

import com.woorisai.support.error.ApplicationException;

class InvalidDiaryRequestException extends ApplicationException {

    InvalidDiaryRequestException() {
        super(DiaryError.INVALID_REQUEST, "Diary request is invalid");
    }
}

class DiaryEntryNotFoundException extends ApplicationException {

    DiaryEntryNotFoundException() {
        super(DiaryError.NOT_FOUND, "Diary entry was not found");
    }
}

class DiaryCommentNotFoundException extends ApplicationException {

    DiaryCommentNotFoundException() {
        super(DiaryError.NOT_FOUND, "Diary comment was not found");
    }
}

class DiaryMediaUploadNotFoundException extends ApplicationException {

    DiaryMediaUploadNotFoundException() {
        super(DiaryError.NOT_FOUND, "Diary media upload was not found");
    }
}

class DiaryMediaForbiddenException extends ApplicationException {

    DiaryMediaForbiddenException() {
        super(DiaryError.FORBIDDEN, "Diary media upload belongs to another participant");
    }
}

class DiaryMutationForbiddenException extends ApplicationException {

    DiaryMutationForbiddenException() {
        super(DiaryError.FORBIDDEN, "Diary resource cannot be changed by this participant");
    }
}

class DiaryConflictException extends ApplicationException {

    DiaryConflictException() {
        super(DiaryError.CONFLICT, "Diary request conflicts with current state");
    }

    DiaryConflictException(Throwable cause) {
        super(DiaryError.CONFLICT, "Diary request conflicts with current state", cause);
    }
}

class DiaryUnavailableException extends ApplicationException {

    DiaryUnavailableException() {
        super(DiaryError.UNAVAILABLE, "Diary is not available");
    }

    DiaryUnavailableException(Throwable cause) {
        super(DiaryError.UNAVAILABLE, "Diary is not available", cause);
    }
}
