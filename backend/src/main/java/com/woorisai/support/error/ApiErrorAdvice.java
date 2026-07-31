package com.woorisai.support.error;

import java.util.List;

/**
 * Builds the production error advice for standalone MockMvc tests.
 *
 * <p>Controller tests must exercise the same advice the application runs, otherwise they stop being
 * evidence about the published contract. The advice is package-private, so this factory is what
 * modules use to obtain it.
 */
public final class ApiErrorAdvice {

    private ApiErrorAdvice() {}

    /**
     * @param handlerFailures mappings for the controllers under test
     */
    public static Object of(HandlerFailures... handlerFailures) {
        return new ApiControllerAdvice(List.of(handlerFailures));
    }
}
