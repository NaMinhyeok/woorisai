package com.woorisai.support.error;

import lombok.Getter;
import lombok.experimental.Accessors;
import org.springframework.boot.logging.LogLevel;
import org.springframework.http.HttpStatus;

@Getter
@Accessors(fluent = true)
public enum CommonError implements ErrorDescriptor {
    UNSUPPORTED_MEDIA_TYPE(
            HttpStatus.UNSUPPORTED_MEDIA_TYPE,
            "UNSUPPORTED_MEDIA_TYPE",
            "Unsupported media type",
            "Content-Type must be application/json.",
            LogLevel.INFO);

    private final HttpStatus status;
    private final String code;
    private final String title;
    private final String detail;
    private final LogLevel logLevel;

    CommonError(HttpStatus status, String code, String title, String detail, LogLevel logLevel) {
        this.status = status;
        this.code = code;
        this.title = title;
        this.detail = detail;
        this.logLevel = logLevel;
    }
}
