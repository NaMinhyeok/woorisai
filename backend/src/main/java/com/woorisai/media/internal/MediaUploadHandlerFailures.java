package com.woorisai.media.internal;

import com.woorisai.support.error.ErrorDescriptor;
import com.woorisai.support.error.HandlerFailures;
import java.util.Optional;
import org.springframework.stereotype.Component;

@Component
class MediaUploadHandlerFailures implements HandlerFailures {

    @Override
    public Class<?> handlerType() {
        return MediaUploadController.class;
    }

    @Override
    public Optional<ErrorDescriptor> invalidRequest() {
        return Optional.of(MediaError.INVALID_UPLOAD_REQUEST);
    }

    @Override
    public Optional<ErrorDescriptor> unavailable() {
        return Optional.of(MediaError.UPLOADS_UNAVAILABLE);
    }
}
