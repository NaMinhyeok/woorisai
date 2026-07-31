package com.woorisai.support.error;

import java.util.Optional;

// Framework exceptions carry no wire contract, and the published code for them differs per
// controller: an unreadable body is INVALID_DIARY_REQUEST on the diary API and
// INVALID_MEDIA_UPLOAD_REQUEST on the upload API. Each module contributes this mapping so the
// single advice never has to know which modules exist. An empty result leaves the exception to
// Spring's default handling instead of borrowing another module's code.
public interface HandlerFailures {

    Class<?> handlerType();

    default Optional<ErrorDescriptor> invalidRequest() {
        return Optional.empty();
    }

    default Optional<ErrorDescriptor> conflict() {
        return Optional.empty();
    }

    default Optional<ErrorDescriptor> unavailable() {
        return Optional.empty();
    }
}
