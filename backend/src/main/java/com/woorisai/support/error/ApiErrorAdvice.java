package com.woorisai.support.error;

import java.util.List;

// Standalone MockMvc tests must run the advice the application runs, and the advice itself is
// package-private.
public final class ApiErrorAdvice {

    private ApiErrorAdvice() {}

    public static Object of(HandlerFailures... handlerFailures) {
        return new ApiControllerAdvice(List.of(handlerFailures));
    }
}
