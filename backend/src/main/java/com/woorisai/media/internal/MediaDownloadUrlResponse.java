package com.woorisai.media.internal;

import java.net.URI;
import java.time.Instant;

record MediaDownloadUrlResponse(
        URI downloadUrl,
        Instant expiresAt) {

    static MediaDownloadUrlResponse from(MediaDownloadGrant grant) {
        if (grant == null) {
            throw new MediaAttachmentDownloadUnavailableException();
        }
        return new MediaDownloadUrlResponse(grant.downloadUrl(), grant.expiresAt());
    }
}
