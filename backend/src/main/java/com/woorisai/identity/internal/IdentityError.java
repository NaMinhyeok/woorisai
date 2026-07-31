package com.woorisai.identity.internal;

import com.woorisai.support.error.ErrorDescriptor;
import lombok.Getter;
import lombok.experimental.Accessors;
import org.springframework.boot.logging.LogLevel;
import org.springframework.http.HttpStatus;

@Getter
@Accessors(fluent = true)
enum IdentityError implements ErrorDescriptor {
    AUTHENTICATION_REQUIRED(
            HttpStatus.UNAUTHORIZED,
            "AUTHENTICATION_REQUIRED",
            "Authentication required",
            "Valid HTTP Basic participant credentials are required.",
            LogLevel.INFO),
    ACCESS_DENIED(
            HttpStatus.FORBIDDEN,
            "ACCESS_DENIED",
            "Access denied",
            "Access to this resource is denied.",
            LogLevel.INFO),
    AUTHENTICATION_UNAVAILABLE(
            HttpStatus.SERVICE_UNAVAILABLE,
            "AUTHENTICATION_UNAVAILABLE",
            "Authentication unavailable",
            "Authentication is temporarily unavailable.",
            LogLevel.WARN),
    LOGIN_OPTIONS_UNAVAILABLE(
            HttpStatus.SERVICE_UNAVAILABLE,
            "LOGIN_OPTIONS_UNAVAILABLE",
            "Login options unavailable",
            "The participant login options are temporarily unavailable.",
            LogLevel.WARN);

    private final HttpStatus status;
    private final String code;
    private final String title;
    private final String detail;
    private final LogLevel logLevel;

    IdentityError(HttpStatus status, String code, String title, String detail, LogLevel logLevel) {
        this.status = status;
        this.code = code;
        this.title = title;
        this.detail = detail;
        this.logLevel = logLevel;
    }
}
