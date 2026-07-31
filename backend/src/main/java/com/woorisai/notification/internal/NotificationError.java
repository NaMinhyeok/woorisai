package com.woorisai.notification.internal;

import com.woorisai.support.error.ErrorDescriptor;
import org.springframework.boot.logging.LogLevel;
import org.springframework.http.HttpStatus;

// NotificationApiProblem omits instance, so these failures must not expose it.
enum NotificationError implements ErrorDescriptor {
    INVALID_FID(
            HttpStatus.BAD_REQUEST,
            "INVALID_NOTIFICATION_FID",
            "Invalid notification FID request",
            "Request must contain one valid Firebase installation ID.",
            LogLevel.INFO),
    FID_UNAVAILABLE(
            HttpStatus.SERVICE_UNAVAILABLE,
            "NOTIFICATION_FID_UNAVAILABLE",
            "Notification FID service unavailable",
            "Notification FID service is temporarily unavailable.",
            LogLevel.WARN);

    @Override
    public boolean exposesInstance() {
        return false;
    }

    private final HttpStatus status;
    private final String code;
    private final String title;
    private final String detail;
    private final LogLevel logLevel;

    NotificationError(HttpStatus status, String code, String title, String detail, LogLevel logLevel) {
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
