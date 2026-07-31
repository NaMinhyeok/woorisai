package com.woorisai.media.internal;

import com.woorisai.support.error.ErrorDescriptor;
import org.springframework.boot.logging.LogLevel;
import org.springframework.http.HttpStatus;

enum MediaError implements ErrorDescriptor {
    INVALID_UPLOAD_REQUEST(
            HttpStatus.BAD_REQUEST,
            "INVALID_MEDIA_UPLOAD_REQUEST",
            "Invalid media upload request",
            "The media upload request is invalid.",
            LogLevel.INFO),
    UPLOAD_FORBIDDEN(
            HttpStatus.FORBIDDEN,
            "MEDIA_UPLOAD_FORBIDDEN",
            "Media upload forbidden",
            "The media upload is not owned by the authenticated participant.",
            LogLevel.INFO),
    UPLOAD_NOT_FOUND(
            HttpStatus.NOT_FOUND,
            "MEDIA_UPLOAD_NOT_FOUND",
            "Media upload not found",
            "The media upload or authorized parent was not found.",
            LogLevel.INFO),
    UPLOAD_CONFLICT(
            HttpStatus.CONFLICT,
            "MEDIA_UPLOAD_CONFLICT",
            "Media upload conflict",
            "The media upload cannot be processed in its current state.",
            LogLevel.INFO),
    UPLOADS_UNAVAILABLE(
            HttpStatus.SERVICE_UNAVAILABLE,
            "MEDIA_UPLOADS_UNAVAILABLE",
            "Media uploads unavailable",
            "Media uploads are temporarily unavailable.",
            LogLevel.WARN),
    INVALID_DOWNLOAD_REQUEST(
            HttpStatus.BAD_REQUEST,
            "INVALID_MEDIA_DOWNLOAD_REQUEST",
            "Invalid media download request",
            "The media download request is invalid.",
            LogLevel.INFO),
    ATTACHMENT_NOT_FOUND(
            HttpStatus.NOT_FOUND,
            "MEDIA_ATTACHMENT_NOT_FOUND",
            "Media attachment not found",
            "The media attachment was not found.",
            LogLevel.INFO),
    DOWNLOAD_UNAVAILABLE(
            HttpStatus.SERVICE_UNAVAILABLE,
            "MEDIA_DOWNLOAD_UNAVAILABLE",
            "Media download unavailable",
            "Media download is temporarily unavailable.",
            LogLevel.WARN);

    private final HttpStatus status;
    private final String code;
    private final String title;
    private final String detail;
    private final LogLevel logLevel;

    MediaError(HttpStatus status, String code, String title, String detail, LogLevel logLevel) {
        this.status = status;
        this.code = code;
        this.title = title;
        this.detail = detail;
        this.logLevel = logLevel;
    }

    @Override
    public HttpStatus status() {
        return status;
    }

    @Override
    public String code() {
        return code;
    }

    @Override
    public String title() {
        return title;
    }

    @Override
    public String detail() {
        return detail;
    }

    @Override
    public LogLevel logLevel() {
        return logLevel;
    }
}
