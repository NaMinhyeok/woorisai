package com.woorisai.media.internal;

import com.woorisai.media.MediaKind;
import java.time.Clock;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;
import java.util.function.Supplier;
import org.springframework.dao.DataAccessException;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

class MediaService {

    private final MediaAttachmentRepository attachments;
    private final MediaObjectStorage objects;
    private final MediaPolicy policy;
    private final int downloadUrlTtlSeconds;
    private final Clock clock;
    private final Supplier<UUID> uploadIds;

    MediaService(
            MediaAttachmentRepository attachments,
            MediaObjectStorage objects,
            MediaPolicy policy,
            int downloadUrlTtlSeconds,
            Clock clock,
            Supplier<UUID> uploadIds) {
        this.attachments = Objects.requireNonNull(attachments, "attachments");
        this.objects = Objects.requireNonNull(objects, "objects");
        this.policy = Objects.requireNonNull(policy, "policy");
        this.downloadUrlTtlSeconds = MediaUrlTtl.requireSeconds(
                downloadUrlTtlSeconds,
                () -> new IllegalArgumentException("Download URL TTL is invalid"));
        this.clock = Objects.requireNonNull(clock, "clock");
        this.uploadIds = Objects.requireNonNull(uploadIds, "uploadIds");
    }

    @Transactional
    InitiatedMediaUpload initiate(
            long uploaderId,
            MediaPurpose purpose,
            MediaKind kind,
            String fileName,
            String contentType,
            long byteSize) {
        ValidatedMediaUpload requested = policy.validate(
                uploaderId,
                purpose,
                kind,
                fileName,
                contentType,
                byteSize);
        UUID uploadId = requireUploadId(uploadIds.get());
        Instant issuedAt = currentTime(MediaUploadInitiationUnavailableException::new);
        String stagingKey = stagingKey(uploadId);
        var pending = MediaAttachment.pending(
                uploadId,
                requested.uploaderId(),
                requested.purpose(),
                requested.kind(),
                stagingKey,
                requested.originalName(),
                requested.contentType(),
                requested.expectedSize(),
                issuedAt);

        try {
            attachments.saveAndFlush(pending);
            var uploadUrl = objects.presignUpload(new UploadPresignRequest(
                    stagingKey,
                    requested.contentType(),
                    requested.expectedSize(),
                    MediaPolicy.PRIVATE_CACHE_CONTROL,
                    policy.uploadUrlTtlSeconds()));
            return new InitiatedMediaUpload(
                    uploadId,
                    uploadUrl,
                    requested.contentType(),
                    issuedAt.plusSeconds(policy.uploadUrlTtlSeconds()));
        } catch (DataAccessException | MediaObjectStorageException exception) {
            throw new MediaUploadInitiationUnavailableException(exception);
        }
    }

    @Transactional
    CompletedMediaUpload complete(long uploaderId, UUID uploadId) {
        validateUploadReference(
                uploaderId, uploadId, InvalidMediaUploadCompletionRequestException::new);
        MediaAttachment attachment;
        try {
            attachment = attachments.findByIdForUpdate(uploadId)
                    .orElseThrow(MediaUploadNotFoundException::new);
        } catch (MediaUploadNotFoundException exception) {
            throw exception;
        } catch (DataAccessException exception) {
            throw new MediaUploadCompletionUnavailableException(exception);
        }
        if (attachment.getUploaderId() != uploaderId) {
            throw new MediaUploadCompletionForbiddenException();
        }
        if (attachment.getStatus() == MediaStatus.READY) {
            return completed(attachment);
        }
        if (attachment.getStatus() != MediaStatus.PENDING || !attachment.isParentless()) {
            throw new MediaUploadCompletionConflictException();
        }

        String stagingKey = attachment.getObjectKey();
        String finalKey = finalKey(attachment.getId());
        try {
            StoredMediaObject staging = objects.inspect(stagingKey);
            validateStoredObject(attachment, staging);
            objects.copy(new MediaObjectCopy(
                    stagingKey,
                    finalKey,
                    attachment.getContentType(),
                    attachment.getOriginalName()));
            StoredMediaObject promoted = objects.inspect(finalKey);
            validateStoredObject(attachment, promoted);
            attachment.complete(
                    finalKey,
                    promoted.size(),
                    currentTime(MediaUploadCompletionUnavailableException::new));
            attachments.flush();
            deleteAfterCommit(stagingKey);
            return completed(attachment);
        } catch (MediaObjectNotFoundException exception) {
            throw new MediaUploadCompletionConflictException();
        } catch (DataAccessException | MediaObjectStorageException exception) {
            throw new MediaUploadCompletionUnavailableException(exception);
        }
    }

    @Transactional
    void discard(long uploaderId, UUID uploadId) {
        validateUploadReference(
                uploaderId, uploadId, InvalidMediaUploadDiscardRequestException::new);
        MediaAttachment attachment;
        try {
            attachment = attachments.findByIdForUpdate(uploadId).orElse(null);
        } catch (DataAccessException exception) {
            throw new MediaUploadDiscardUnavailableException(exception);
        }
        if (attachment == null) {
            return;
        }
        if (attachment.getUploaderId() != uploaderId) {
            throw new MediaUploadDiscardForbiddenException();
        }
        if (!attachment.isParentless()) {
            throw new MediaUploadDiscardConflictException();
        }

        String objectKey = attachment.getObjectKey();
        try {
            attachments.delete(attachment);
            attachments.flush();
            deleteAfterCommit(objectKey);
        } catch (DataAccessException exception) {
            throw new MediaUploadDiscardUnavailableException(exception);
        }
    }

    @Transactional(readOnly = true)
    MediaDownloadGrant download(long actorId, UUID attachmentId) {
        if (actorId <= 0 || attachmentId == null) {
            throw new InvalidMediaDownloadRequestException();
        }
        MediaAttachment attachment;
        try {
            attachment = attachments.findById(attachmentId)
                    .orElseThrow(MediaAttachmentNotFoundException::new);
        } catch (MediaAttachmentNotFoundException exception) {
            throw exception;
        } catch (DataAccessException exception) {
            throw new MediaDownloadUnavailableException(exception);
        }
        if (!attachment.isParentedReady()) {
            throw new MediaAttachmentNotFoundException();
        }

        Instant issuedAt = currentTime(MediaDownloadUnavailableException::new);
        try {
            var url = objects.presignDownload(new DownloadPresignRequest(
                    attachment.getObjectKey(), downloadUrlTtlSeconds));
            return new MediaDownloadGrant(
                    url, issuedAt.plusSeconds(downloadUrlTtlSeconds));
        } catch (MediaObjectStorageException exception) {
            throw new MediaDownloadUnavailableException(exception);
        }
    }

    private void validateStoredObject(
            MediaAttachment attachment,
            StoredMediaObject stored) {
        if (stored == null
                || stored.size() != attachment.getExpectedSize()
                || !attachment.getContentType().equals(stored.contentType())
                || !MediaContentSignature.matches(
                        attachment.getContentType(), stored.initialBytes())) {
            throw new MediaUploadContentRejectedException();
        }
    }

    private CompletedMediaUpload completed(MediaAttachment attachment) {
        Long actualSize = attachment.getActualSize();
        if (actualSize == null) {
            throw new MediaUploadCompletionUnavailableException();
        }
        return new CompletedMediaUpload(
                attachment.getId(),
                attachment.getKind(),
                attachment.getOriginalName(),
                attachment.getContentType(),
                actualSize);
    }

    private void deleteAfterCommit(String objectKey) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            throw new IllegalStateException("Transaction synchronization is required");
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                try {
                    objects.delete(objectKey);
                } catch (RuntimeException ignored) {
                    // The database deletion is authoritative; an R2 orphan is accepted.
                }
            }
        });
    }

    private static void validateUploadReference(
            long uploaderId,
            UUID uploadId,
            Supplier<? extends RuntimeException> failure) {
        if (uploaderId <= 0 || uploadId == null) {
            throw failure.get();
        }
    }

    private static UUID requireUploadId(UUID uploadId) {
        if (uploadId == null || uploadId.version() != 4) {
            throw new MediaUploadInitiationUnavailableException();
        }
        return uploadId;
    }

    private static String stagingKey(UUID uploadId) {
        return "pending/" + uploadId;
    }

    private static String finalKey(UUID uploadId) {
        return "media/" + uploadId;
    }

    private Instant currentTime(Supplier<? extends RuntimeException> failure) {
        try {
            return Objects.requireNonNull(clock.instant(), "clock instant");
        } catch (RuntimeException exception) {
            RuntimeException mapped = failure.get();
            if (mapped.getCause() == null) {
                mapped.initCause(exception);
            }
            throw mapped;
        }
    }
}
