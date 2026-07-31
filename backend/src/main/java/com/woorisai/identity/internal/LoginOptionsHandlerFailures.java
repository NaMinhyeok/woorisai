package com.woorisai.identity.internal;

import com.woorisai.support.error.ErrorDescriptor;
import com.woorisai.support.error.HandlerFailures;
import java.util.Optional;
import org.springframework.stereotype.Component;

/**
 * Framework failures reported under the login options contract.
 */
@Component
class LoginOptionsHandlerFailures implements HandlerFailures {

    @Override
    public Class<?> handlerType() {
        return LoginOptionsController.class;
    }

    @Override
    public Optional<ErrorDescriptor> unavailable() {
        return Optional.of(IdentityError.LOGIN_OPTIONS_UNAVAILABLE);
    }
}
