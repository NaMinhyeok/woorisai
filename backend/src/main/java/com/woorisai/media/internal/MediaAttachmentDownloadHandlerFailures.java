package com.woorisai.media.internal;

import com.woorisai.support.error.ErrorDescriptor;
import com.woorisai.support.error.HandlerFailures;
import java.util.Optional;
import org.springframework.stereotype.Component;

/**
 * Framework failures reported under the media download contract.
 *
 * <p>The download API publishes no contract for an unreadable body: it accepts no request body.
 */
@Component
class MediaAttachmentDownloadHandlerFailures implements HandlerFailures {

    @Override
    public Class<?> handlerType() {
        return MediaAttachmentDownloadController.class;
    }

    @Override
    public Optional<ErrorDescriptor> unavailable() {
        return Optional.of(MediaError.DOWNLOAD_UNAVAILABLE);
    }
}
