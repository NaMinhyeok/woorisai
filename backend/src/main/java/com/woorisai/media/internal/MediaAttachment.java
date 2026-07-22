package com.woorisai.media.internal;

import com.woorisai.media.MediaKind;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Getter(AccessLevel.PACKAGE)
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Table(name = "media_attachment")
class MediaAttachment {

    @Id
    @Column(name = "id", nullable = false)
    private UUID id;

    @Column(name = "uploader_id", nullable = false)
    private Long uploaderId;

    @Column(name = "score_change_id")
    private Long scoreChangeId;

    @Column(name = "score_change_comment_id")
    private Long scoreChangeCommentId;

    @Column(name = "diary_entry_id")
    private Long diaryEntryId;

    @Enumerated(EnumType.STRING)
    @Column(name = "purpose", nullable = false, length = 24)
    private MediaPurpose purpose;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, length = 8)
    private MediaKind kind;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 8)
    private MediaStatus status;

    @Column(name = "object_key", nullable = false, unique = true, length = 255)
    private String objectKey;

    @Column(name = "original_name", nullable = false, length = 255)
    private String originalName;

    @Column(name = "content_type", nullable = false, length = 100)
    private String contentType;

    @Column(name = "expected_size", nullable = false)
    private Long expectedSize;

    @Column(name = "actual_size")
    private Long actualSize;

    @Column(name = "position", nullable = false)
    private Short position;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "ready_at")
    private Instant readyAt;

    static MediaAttachment pending(
            UUID id,
            long uploaderId,
            MediaPurpose purpose,
            MediaKind kind,
            String objectKey,
            String originalName,
            String contentType,
            long expectedSize,
            Instant createdAt) {
        var attachment = new MediaAttachment();
        attachment.id = id;
        attachment.uploaderId = uploaderId;
        attachment.purpose = purpose;
        attachment.kind = kind;
        attachment.status = MediaStatus.PENDING;
        attachment.objectKey = objectKey;
        attachment.originalName = originalName;
        attachment.contentType = contentType;
        attachment.expectedSize = expectedSize;
        attachment.position = 0;
        attachment.createdAt = createdAt;
        return attachment;
    }

    void complete(String finalObjectKey, long finalSize, Instant completedAt) {
        if (status != MediaStatus.PENDING || !isParentless()) {
            throw new IllegalStateException("Only a parentless pending upload can become ready");
        }
        status = MediaStatus.READY;
        objectKey = finalObjectKey;
        actualSize = finalSize;
        readyAt = completedAt;
    }

    void attachScoreChange(long parentId) {
        requireReadyAndParentless();
        scoreChangeId = parentId;
        position = 0;
    }

    void attachScoreComment(long parentId, short requestedPosition) {
        requireReadyAndParentless();
        scoreChangeCommentId = parentId;
        position = requestedPosition;
    }

    void attachDiaryEntry(long parentId, short requestedPosition) {
        requireReadyAndParentless();
        diaryEntryId = parentId;
        position = requestedPosition;
    }

    void detach() {
        if (status != MediaStatus.READY) {
            throw new IllegalStateException("Only ready media can be detached");
        }
        scoreChangeId = null;
        scoreChangeCommentId = null;
        diaryEntryId = null;
        position = 0;
    }

    boolean isParentless() {
        return scoreChangeId == null && scoreChangeCommentId == null && diaryEntryId == null;
    }

    boolean isParentedReady() {
        if (status != MediaStatus.READY || parentCount() != 1) {
            return false;
        }
        return switch (purpose) {
            case SCORE_CHANGE -> scoreChangeId != null;
            case SCORE_CHANGE_COMMENT -> scoreChangeCommentId != null;
            case DIARY_ENTRY -> diaryEntryId != null;
        };
    }

    boolean isAttachedToDiary(long parentId) {
        return status == MediaStatus.READY
                && scoreChangeId == null
                && scoreChangeCommentId == null
                && diaryEntryId != null
                && diaryEntryId == parentId;
    }

    private int parentCount() {
        int count = scoreChangeId == null ? 0 : 1;
        count += scoreChangeCommentId == null ? 0 : 1;
        count += diaryEntryId == null ? 0 : 1;
        return count;
    }

    private void requireReadyAndParentless() {
        if (status != MediaStatus.READY || !isParentless()) {
            throw new IllegalStateException("Only parentless ready media can be attached");
        }
    }
}
