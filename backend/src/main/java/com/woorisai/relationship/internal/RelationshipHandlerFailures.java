package com.woorisai.relationship.internal;

import com.woorisai.support.error.ErrorDescriptor;
import com.woorisai.support.error.HandlerFailures;
import java.util.Optional;
import org.springframework.stereotype.Component;

/**
 * Framework failures reported under the relationship contract.
 */
@Component
class RelationshipHandlerFailures implements HandlerFailures {

    @Override
    public Class<?> handlerType() {
        return RelationshipController.class;
    }

    @Override
    public Optional<ErrorDescriptor> invalidRequest() {
        return Optional.of(RelationshipError.INVALID_REQUEST);
    }
    @Override
    public Optional<ErrorDescriptor> conflict() {
        return Optional.of(RelationshipError.CONFLICT);
    }
    @Override
    public Optional<ErrorDescriptor> unavailable() {
        return Optional.of(RelationshipError.UNAVAILABLE);
    }
}
