package com.woorisai.support.error;

import java.net.URI;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;

public final class ApiProblems {

    // Spring fills a null instance with the current request path while rendering, so leaving the
    // field unset does not keep it out of the body. Serializing an empty URI suppresses that
    // default and ProblemDetail then omits the property, which NotificationApiProblem requires.
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
