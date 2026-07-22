package com.woorisai.media.internal;

import java.util.UUID;

record CompletedMediaUploadResponse(
        UUID uploadId,
        String kind,
        String fileName,
        String contentType,
        long byteSize) {

    static CompletedMediaUploadResponse from(CompletedMediaUpload upload) {
        if (upload == null) {
            throw new MediaUploadsUnavailableHttpException();
        }
        return new CompletedMediaUploadResponse(
                upload.uploadId(),
                switch (upload.kind()) {
                    case IMAGE -> "image";
                    case VIDEO -> "video";
                },
                upload.fileName(),
                upload.contentType(),
                upload.byteSize());
    }
}
