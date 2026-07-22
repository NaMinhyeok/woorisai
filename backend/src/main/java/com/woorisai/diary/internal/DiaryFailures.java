package com.woorisai.diary.internal;

class InvalidDiaryRequestException extends RuntimeException {

    InvalidDiaryRequestException() {
        super("Diary request is invalid");
    }
}

class DiaryEntryNotFoundException extends RuntimeException {

    DiaryEntryNotFoundException() {
        super("Diary entry was not found");
    }
}

class DiaryCommentNotFoundException extends RuntimeException {

    DiaryCommentNotFoundException() {
        super("Diary comment was not found");
    }
}

class DiaryMutationForbiddenException extends RuntimeException {

    DiaryMutationForbiddenException() {
        super("Diary resource cannot be changed by this participant");
    }
}

class DiaryConflictException extends RuntimeException {

    DiaryConflictException() {
        super("Diary request conflicts with current state");
    }

    DiaryConflictException(Throwable cause) {
        super("Diary request conflicts with current state", cause);
    }
}

class DiaryUnavailableException extends RuntimeException {

    DiaryUnavailableException() {
        super("Diary is not available");
    }

    DiaryUnavailableException(Throwable cause) {
        super("Diary is not available", cause);
    }
}
