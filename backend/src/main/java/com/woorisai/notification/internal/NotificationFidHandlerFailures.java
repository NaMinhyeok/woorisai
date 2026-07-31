package com.woorisai.notification.internal;

import com.woorisai.support.error.ErrorDescriptor;
import com.woorisai.support.error.HandlerFailures;
import java.util.Optional;
import org.springframework.stereotype.Component;

/**
 * Framework failures reported under the notification FID contract.
 */
@Component
class NotificationFidHandlerFailures implements HandlerFailures {

    @Override
    public Class<?> handlerType() {
        return NotificationFidController.class;
    }

    @Override
    public Optional<ErrorDescriptor> invalidRequest() {
        return Optional.of(NotificationError.INVALID_FID);
    }
    @Override
    public Optional<ErrorDescriptor> unavailable() {
        return Optional.of(NotificationError.FID_UNAVAILABLE);
    }
}
