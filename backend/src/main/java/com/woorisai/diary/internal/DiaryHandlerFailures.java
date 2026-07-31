package com.woorisai.diary.internal;

import com.woorisai.support.error.ErrorDescriptor;
import com.woorisai.support.error.HandlerFailures;
import java.util.Optional;
import org.springframework.stereotype.Component;

/**
 * Framework failures reported under the diary contract.
 */
@Component
class DiaryHandlerFailures implements HandlerFailures {

    @Override
    public Class<?> handlerType() {
        return DiaryController.class;
    }

    @Override
    public Optional<ErrorDescriptor> invalidRequest() {
        return Optional.of(DiaryError.INVALID_REQUEST);
    }
    @Override
    public Optional<ErrorDescriptor> conflict() {
        return Optional.of(DiaryError.CONFLICT);
    }
    @Override
    public Optional<ErrorDescriptor> unavailable() {
        return Optional.of(DiaryError.UNAVAILABLE);
    }
}
