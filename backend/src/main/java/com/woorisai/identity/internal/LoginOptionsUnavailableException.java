package com.woorisai.identity.internal;

import com.woorisai.support.error.ApplicationException;

/**
 * Login options could not be produced.
 *
 * <p>The participant directory reports an unusable pair with its own exception, which carries no
 * wire contract because each consumer publishes a different code for it. This module translates it
 * at the controller boundary into the contract the login options endpoint publishes.
 */
final class LoginOptionsUnavailableException extends ApplicationException {

    LoginOptionsUnavailableException(Throwable cause) {
        super(IdentityError.LOGIN_OPTIONS_UNAVAILABLE, "Login options are not available", cause);
    }
}
