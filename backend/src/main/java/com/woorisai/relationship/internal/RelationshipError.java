package com.woorisai.relationship.internal;

import com.woorisai.support.error.ErrorDescriptor;
import org.springframework.boot.logging.LogLevel;
import org.springframework.http.HttpStatus;

enum RelationshipError implements ErrorDescriptor {
    INVALID_REQUEST(
            HttpStatus.BAD_REQUEST,
            "INVALID_RELATIONSHIP_REQUEST",
            "Invalid relationship request",
            "The relationship request is invalid.",
            LogLevel.INFO),
    NOT_FOUND(
            HttpStatus.NOT_FOUND,
            "RELATIONSHIP_NOT_FOUND",
            "Relationship resource not found",
            "The requested relationship resource was not found.",
            LogLevel.INFO),
    FORBIDDEN(
            HttpStatus.FORBIDDEN,
            "RELATIONSHIP_FORBIDDEN",
            "Relationship access denied",
            "Access to this relationship resource is denied.",
            LogLevel.INFO),
    CONFLICT(
            HttpStatus.CONFLICT,
            "RELATIONSHIP_CONFLICT",
            "Relationship conflict",
            "The relationship request conflicts with current state.",
            LogLevel.INFO),
    UNAVAILABLE(
            HttpStatus.SERVICE_UNAVAILABLE,
            "RELATIONSHIP_UNAVAILABLE",
            "Relationship unavailable",
            "Relationship data is temporarily unavailable.",
            LogLevel.WARN);

    private final HttpStatus status;
    private final String code;
    private final String title;
    private final String detail;
    private final LogLevel logLevel;

    RelationshipError(HttpStatus status, String code, String title, String detail, LogLevel logLevel) {
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
