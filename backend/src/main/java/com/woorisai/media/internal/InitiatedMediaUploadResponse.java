package com.woorisai.media.internal;

import java.net.URI;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

record InitiatedMediaUploadResponse(
        UUID uploadId,
        URI uploadUrl,
        Map<String, String> requiredHeaders,
        Instant expiresAt) {

    InitiatedMediaUploadResponse {
        requiredHeaders = Map.copyOf(requiredHeaders);
    }

    static InitiatedMediaUploadResponse from(InitiatedMediaUpload upload) {
        if (upload == null) {
            throw new MediaUploadsUnavailableHttpException();
        }
        return new InitiatedMediaUploadResponse(
                upload.uploadId(),
                upload.uploadUrl(),
                Map.of(
                        "Content-Type", upload.contentType(),
                        "Cache-Control", MediaPolicy.PRIVATE_CACHE_CONTROL),
                upload.expiresAt());
    }
}
