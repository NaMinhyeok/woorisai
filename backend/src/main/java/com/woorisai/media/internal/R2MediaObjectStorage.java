package com.woorisai.media.internal;

import java.io.IOException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Locale;
import java.util.Objects;
import software.amazon.awssdk.awscore.exception.AwsErrorDetails;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.CopyObjectRequest;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;
import software.amazon.awssdk.services.s3.model.MetadataDirective;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

final class R2MediaObjectStorage implements MediaObjectStorage {

    private static final String INSPECTION_RANGE =
            "bytes=0-" + (StoredMediaObject.MAXIMUM_INITIAL_BYTES - 1);
    private static final char[] HEX = "0123456789ABCDEF".toCharArray();

    private final S3Client client;
    private final S3Presigner presigner;
    private final String bucket;

    R2MediaObjectStorage(S3Client client, S3Presigner presigner, String bucket) {
        this.client = Objects.requireNonNull(client, "client");
        this.presigner = Objects.requireNonNull(presigner, "presigner");
        this.bucket = requireBucket(bucket);
    }

    @Override
    public URI presignUpload(UploadPresignRequest request) {
        try {
            Objects.requireNonNull(request, "request");
            PutObjectRequest put = PutObjectRequest.builder()
                    .bucket(bucket)
                    .key(request.objectKey())
                    .contentType(request.contentType())
                    .contentLength(request.contentLength())
                    .cacheControl(request.cacheControl())
                    .build();
            return presigner.presignPutObject(PutObjectPresignRequest.builder()
                            .signatureDuration(Duration.ofSeconds(request.expiresInSeconds()))
                            .putObjectRequest(put)
                            .build())
                    .url()
                    .toURI();
        } catch (Exception exception) {
            throw new MediaObjectStorageException(exception);
        }
    }

    @Override
    public StoredMediaObject inspect(String objectKey) {
        try {
            HeadObjectResponse head = Objects.requireNonNull(client.headObject(
                    HeadObjectRequest.builder().bucket(bucket).key(objectKey).build()));
            long size = requireContentLength(head.contentLength());
            String contentType = normalizeContentType(head.contentType());
            byte[] initialBytes = size == 0
                    ? new byte[0]
                    : readInitialBytes(objectKey);
            return new StoredMediaObject(size, contentType, initialBytes);
        } catch (RuntimeException exception) {
            if (isNotFound(exception)) {
                throw new MediaObjectNotFoundException(exception);
            }
            throw new MediaObjectStorageException(exception);
        } catch (IOException exception) {
            throw new MediaObjectStorageException(exception);
        }
    }

    private byte[] readInitialBytes(String objectKey) throws IOException {
        try (var response = Objects.requireNonNull(client.getObject(GetObjectRequest.builder()
                .bucket(bucket)
                .key(objectKey)
                .range(INSPECTION_RANGE)
                .build()))) {
            return response.readNBytes(StoredMediaObject.MAXIMUM_INITIAL_BYTES);
        }
    }

    @Override
    public void copy(MediaObjectCopy request) {
        try {
            Objects.requireNonNull(request, "request");
            Objects.requireNonNull(client.copyObject(CopyObjectRequest.builder()
                    .destinationBucket(bucket)
                    .destinationKey(request.destinationKey())
                    .sourceBucket(bucket)
                    .sourceKey(request.sourceKey())
                    .metadataDirective(MetadataDirective.REPLACE)
                    .contentType(request.contentType())
                    .cacheControl(MediaPolicy.PRIVATE_CACHE_CONTROL)
                    .contentDisposition(contentDisposition(request.originalName()))
                    .build()));
        } catch (RuntimeException exception) {
            throw new MediaObjectStorageException(exception);
        }
    }

    @Override
    public URI presignDownload(DownloadPresignRequest request) {
        try {
            Objects.requireNonNull(request, "request");
            GetObjectRequest get = GetObjectRequest.builder()
                    .bucket(bucket)
                    .key(request.objectKey())
                    .build();
            return presigner.presignGetObject(GetObjectPresignRequest.builder()
                            .signatureDuration(Duration.ofSeconds(request.expiresInSeconds()))
                            .getObjectRequest(get)
                            .build())
                    .url()
                    .toURI();
        } catch (Exception exception) {
            throw new MediaObjectStorageException(exception);
        }
    }

    @Override
    public void delete(String objectKey) {
        try {
            Objects.requireNonNull(client.deleteObject(DeleteObjectRequest.builder()
                    .bucket(bucket)
                    .key(objectKey)
                    .build()));
        } catch (RuntimeException exception) {
            throw new MediaObjectStorageException(exception);
        }
    }

    private static String requireBucket(String bucket) {
        if (bucket == null || bucket.isBlank()) {
            throw new IllegalArgumentException("bucket must not be blank");
        }
        return bucket;
    }

    private static long requireContentLength(Long contentLength) {
        if (contentLength == null || contentLength < 0) {
            throw new IllegalStateException("Stored object content length is invalid");
        }
        return contentLength;
    }

    private static String normalizeContentType(String contentType) {
        if (contentType == null) {
            return "";
        }
        return contentType.split(";", 2)[0].trim().toLowerCase(Locale.ROOT);
    }

    private static boolean isNotFound(Throwable failure) {
        Throwable current = failure;
        while (current != null) {
            if (current instanceof NoSuchKeyException) {
                return true;
            }
            if (current instanceof S3Exception s3Exception) {
                AwsErrorDetails details = s3Exception.awsErrorDetails();
                String code = details == null ? null : details.errorCode();
                if ("404".equals(code)
                        || "NoSuchKey".equals(code)
                        || "NotFound".equals(code)
                        || (code == null && s3Exception.statusCode() == 404)) {
                    return true;
                }
            }
            Throwable cause = current.getCause();
            if (cause == current) {
                break;
            }
            current = cause;
        }
        return false;
    }

    private static String contentDisposition(String originalName) {
        return "inline; filename*=UTF-8''" + percentEncode(
                Objects.requireNonNull(originalName, "originalName"));
    }

    private static String percentEncode(String value) {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        StringBuilder encoded = new StringBuilder(bytes.length);
        for (byte current : bytes) {
            int unsigned = current & 0xff;
            if (isSafeAttributeCharacter(unsigned)) {
                encoded.append((char) unsigned);
            } else {
                encoded.append('%');
                encoded.append(HEX[unsigned >>> 4]);
                encoded.append(HEX[unsigned & 0x0f]);
            }
        }
        return encoded.toString();
    }

    private static boolean isSafeAttributeCharacter(int value) {
        return value >= 'a' && value <= 'z'
                || value >= 'A' && value <= 'Z'
                || value >= '0' && value <= '9'
                || value == '-'
                || value == '.'
                || value == '_'
                || value == '~'
                || value == '!'
                || value == '#'
                || value == '$'
                || value == '&'
                || value == '+'
                || value == '^'
                || value == '`'
                || value == '|';
    }
}
