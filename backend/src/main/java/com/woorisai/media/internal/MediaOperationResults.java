package com.woorisai.media.internal;

import com.woorisai.media.MediaKind;
import java.net.URI;
import java.time.Instant;
import java.util.UUID;
import java.util.function.Function;

record InitiatedMediaUpload(
        UUID uploadId,
        URI uploadUrl,
        String contentType,
        Instant expiresAt) {

    InitiatedMediaUpload {
        if (uploadId == null
                || contentType == null
                || contentType.isBlank()
                || expiresAt == null) {
            throw new MediaUploadInitiationUnavailableException();
        }
        uploadUrl = PrivateMediaUrls.requireHttps(
                uploadUrl, MediaUploadInitiationUnavailableException::new);
    }
}

record CompletedMediaUpload(
        UUID uploadId,
        MediaKind kind,
        String fileName,
        String contentType,
        long byteSize) {

    CompletedMediaUpload {
        if (uploadId == null
                || kind == null
                || fileName == null
                || fileName.isEmpty()
                || contentType == null
                || contentType.isEmpty()
                || byteSize <= 0) {
            throw new MediaUploadCompletionUnavailableException();
        }
    }
}

record MediaDownloadGrant(
        URI downloadUrl,
        Instant expiresAt) {

    MediaDownloadGrant {
        if (expiresAt == null) {
            throw new MediaDownloadUnavailableException();
        }
        downloadUrl = PrivateMediaUrls.requireHttps(
                downloadUrl, MediaDownloadUnavailableException::new);
    }
}

final class PrivateMediaUrls {

    private PrivateMediaUrls() {}

    static URI requireHttps(
            URI url,
            Function<Throwable, ? extends RuntimeException> failure) {
        if (url == null
                || !"https".equalsIgnoreCase(url.getScheme())
                || url.getHost() == null
                || url.getHost().isBlank()
                || url.getRawUserInfo() != null
                || url.getRawFragment() != null) {
            throw failure.apply(new IllegalStateException("Presigned media URL is invalid"));
        }
        return "https".equals(url.getScheme())
                ? url
                : URI.create("https:" + url.getRawSchemeSpecificPart());
    }
}
