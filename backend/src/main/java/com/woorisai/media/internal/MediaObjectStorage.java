package com.woorisai.media.internal;

import java.net.URI;
import java.util.Objects;

interface MediaObjectStorage {

    URI presignUpload(UploadPresignRequest request);

    StoredMediaObject inspect(String objectKey);

    void copy(MediaObjectCopy request);

    URI presignDownload(DownloadPresignRequest request);

    void delete(String objectKey);
}

record UploadPresignRequest(
        String objectKey,
        String contentType,
        long contentLength,
        String cacheControl,
        int expiresInSeconds) {}

record DownloadPresignRequest(String objectKey, int expiresInSeconds) {}

record MediaObjectCopy(
        String sourceKey,
        String destinationKey,
        String contentType,
        String originalName) {}

record StoredMediaObject(long size, String contentType, byte[] initialBytes) {

    static final int MAXIMUM_INITIAL_BYTES = 4_096;

    StoredMediaObject {
        contentType = Objects.requireNonNull(contentType, "contentType");
        initialBytes = Objects.requireNonNull(initialBytes, "initialBytes").clone();
        if (size < 0 || initialBytes.length > MAXIMUM_INITIAL_BYTES) {
            throw new IllegalArgumentException("Stored media object metadata is invalid");
        }
    }

    @Override
    public byte[] initialBytes() {
        return initialBytes.clone();
    }
}

final class MediaObjectNotFoundException extends RuntimeException {

    MediaObjectNotFoundException(Throwable cause) {
        super("Private media object was not found", cause);
    }
}

final class MediaObjectStorageException extends RuntimeException {

    MediaObjectStorageException(Throwable cause) {
        super("Private media object storage is not available", cause);
    }
}
