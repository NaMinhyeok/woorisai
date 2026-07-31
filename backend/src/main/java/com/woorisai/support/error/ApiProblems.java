package com.woorisai.support.error;

import java.net.URI;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;

/**
 * Single place where an {@link ErrorDescriptor} becomes an RFC 7807 response.
 *
 * <p>Also used by the Spring Security handlers, which write to the servlet response directly and
 * therefore need the body without a {@link ResponseEntity} around it.
 */
public final class ApiProblems {

    /**
     * Stands in for an absent {@code instance}.
     *
     * <p>Spring fills a null {@code instance} with the current request path while rendering, so
     * leaving the field unset is not enough to keep it out of the body. Serializing an empty URI
     * suppresses that default, and {@code ProblemDetail} then omits the property.
     */
    private static final URI NO_INSTANCE = URI.create("");

    private ApiProblems() {}

    public static ProblemDetail body(ErrorDescriptor error, String requestUri) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(error.status(), error.detail());
        problem.setTitle(error.title());
        problem.setProperty("errorCode", error.code());
        problem.setInstance(error.exposesInstance() ? URI.create(requestUri) : NO_INSTANCE);
        return problem;
    }

    public static ResponseEntity<ProblemDetail> response(ErrorDescriptor error, String requestUri) {
        return ResponseEntity.status(error.status())
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .cacheControl(CacheControl.noStore())
                .body(body(error, requestUri));
    }
}
