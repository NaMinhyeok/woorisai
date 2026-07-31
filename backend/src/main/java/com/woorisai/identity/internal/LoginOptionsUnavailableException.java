package com.woorisai.identity.internal;

import com.woorisai.support.error.ApplicationException;

// The participant directory's own exception carries no wire contract because each consumer
// publishes a different code for it, so this module translates it at the controller boundary.
final class LoginOptionsUnavailableException extends ApplicationException {

    LoginOptionsUnavailableException(Throwable cause) {
        super(IdentityError.LOGIN_OPTIONS_UNAVAILABLE, "Login options are not available", cause);
    }
}
