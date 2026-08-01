package com.woorisai.diary.internal;

import com.woorisai.support.error.ErrorDescriptor;
import lombok.Getter;
import lombok.experimental.Accessors;
import org.springframework.boot.logging.LogLevel;
import org.springframework.http.HttpStatus;

@Getter
@Accessors(fluent = true)
enum DiaryError implements ErrorDescriptor {
    INVALID_REQUEST(
            HttpStatus.BAD_REQUEST,
            "INVALID_DIARY_REQUEST",
            "Invalid diary request",
            "The diary request is invalid.",
            LogLevel.INFO),
    NOT_FOUND(
            HttpStatus.NOT_FOUND,
            "DIARY_NOT_FOUND",
            "Diary resource not found",
            "The requested diary resource was not found.",
            LogLevel.INFO),
    FORBIDDEN(
            HttpStatus.FORBIDDEN,
            "DIARY_FORBIDDEN",
            "Diary mutation forbidden",
            "Only the author can change this diary resource.",
            LogLevel.INFO),
    CONFLICT(
            HttpStatus.CONFLICT,
            "DIARY_CONFLICT",
            "Diary conflict",
            "The diary request conflicts with current state.",
            LogLevel.INFO),
    UNAVAILABLE(
            HttpStatus.SERVICE_UNAVAILABLE,
            "DIARY_UNAVAILABLE",
            "Diary unavailable",
            "Diary data is temporarily unavailable.",
            LogLevel.WARN);

    private final HttpStatus status;
    private final String code;
    private final String title;
    private final String detail;
    private final LogLevel logLevel;

    DiaryError(HttpStatus status, String code, String title, String detail, LogLevel logLevel) {
        this.status = status;
        this.code = code;
        this.title = title;
        this.detail = detail;
        this.logLevel = logLevel;
    }
}
