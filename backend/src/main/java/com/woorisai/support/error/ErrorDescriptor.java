package com.woorisai.support.error;

import org.springframework.boot.logging.LogLevel;
import org.springframework.http.HttpStatus;

public interface ErrorDescriptor {

    HttpStatus status();

    // Fixed by contracts/openapi-v2.yaml. Declared per constant because the published codes
    // follow no derivable rule: INVALID_DIARY_REQUEST inverts the module prefix and
    // UNSUPPORTED_MEDIA_TYPE carries none.
    String code();

    String title();

    String detail();

    LogLevel logLevel();

    // ApiProblem requires instance, NotificationApiProblem omits it.
    default boolean exposesInstance() {
        return true;
    }
}
