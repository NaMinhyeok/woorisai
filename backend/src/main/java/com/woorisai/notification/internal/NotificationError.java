package com.woorisai.notification.internal;

import com.woorisai.support.error.ErrorDescriptor;
import lombok.Getter;
import lombok.experimental.Accessors;
import org.springframework.boot.logging.LogLevel;
import org.springframework.http.HttpStatus;

// NotificationApiProblem omits instance, so these failures must not expose it.
@Getter
@Accessors(fluent = true)
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
    public boolean exposesInstance() {
        return false;
    }
}
