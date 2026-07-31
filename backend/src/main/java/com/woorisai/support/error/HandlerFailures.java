package com.woorisai.support.error;

import java.util.Optional;

/**
 * How one controller reports failures raised by the framework rather than by the module.
 *
 * <p>Spring throws request-binding, locking and data-access exceptions before or around module
 * code, yet the published {@code errorCode} for them differs per controller: an unreadable body is
 * {@code INVALID_DIARY_REQUEST} on the diary API and {@code INVALID_MEDIA_UPLOAD_REQUEST} on the
 * upload API. A module declares that mapping by contributing an implementation of this interface,
 * so the single advice never needs to know which modules exist.
 *
 * <p>An empty result means the controller does not publish a contract for that failure, and the
 * exception keeps its default handling.
 */
public interface HandlerFailures {

    /** Controller this mapping applies to. */
    Class<?> handlerType();

    /** Malformed or unbindable request. */
    default Optional<ErrorDescriptor> invalidRequest() {
        return Optional.empty();
    }

    /** Concurrent modification detected by optimistic locking. */
    default Optional<ErrorDescriptor> conflict() {
        return Optional.empty();
    }

    /** Data access or transaction failure. */
    default Optional<ErrorDescriptor> unavailable() {
        return Optional.empty();
    }
}
