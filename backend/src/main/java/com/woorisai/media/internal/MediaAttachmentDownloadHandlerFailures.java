package com.woorisai.media.internal;

import com.woorisai.support.error.ErrorDescriptor;
import com.woorisai.support.error.HandlerFailures;
import java.util.Optional;
import org.springframework.stereotype.Component;

// No invalidRequest mapping: the download API accepts no request body.
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
