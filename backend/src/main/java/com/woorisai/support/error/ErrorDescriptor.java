package com.woorisai.support.error;

import org.springframework.boot.logging.LogLevel;
import org.springframework.http.HttpStatus;

/**
 * Wire contract of one API failure.
 *
 * <p>Business modules declare their own catalog of descriptors. This module owns only how a
 * descriptor becomes an RFC 7807 response, never what any failure means.
 */
public interface ErrorDescriptor {

    HttpStatus status();

    /**
     * Public {@code errorCode} fixed by {@code contracts/openapi-v2.yaml}. Declared explicitly per
     * constant because the published codes do not follow a derivable naming rule.
     */
    String code();

    String title();

    String detail();

    LogLevel logLevel();

    /**
     * Whether the response carries {@code instance}.
     *
     * <p>{@code ApiProblem} requires it, {@code NotificationApiProblem} omits it. Overriding this
     * to {@code false} is what keeps the notification contract intact.
     */
    default boolean exposesInstance() {
        return true;
    }
}
