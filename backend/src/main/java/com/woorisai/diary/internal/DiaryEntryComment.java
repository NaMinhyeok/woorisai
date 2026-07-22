package com.woorisai.diary.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.Objects;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Getter(AccessLevel.PACKAGE)
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Table(name = "diary_entry_comment")
class DiaryEntryComment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id", nullable = false)
    private Long id;

    @Column(name = "diary_entry_id", nullable = false)
    private long diaryEntryId;

    @Column(name = "author_id", nullable = false)
    private long authorId;

    @Column(name = "content", nullable = false, length = 500)
    private String content;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at")
    private Instant updatedAt;

    @Version
    @Column(name = "version", nullable = false)
    private long version;

    private DiaryEntryComment(
            long diaryEntryId,
            long authorId,
            DiaryCommentContent content,
            Instant createdAt) {
        if (diaryEntryId <= 0 || authorId <= 0) {
            throw new IllegalArgumentException("Diary comment identity is invalid");
        }
        this.diaryEntryId = diaryEntryId;
        this.authorId = authorId;
        this.content = Objects.requireNonNull(content, "content").value();
        this.createdAt = Objects.requireNonNull(createdAt, "createdAt");
    }

    static DiaryEntryComment create(
            long diaryEntryId,
            long authorId,
            DiaryCommentContent content,
            Instant createdAt) {
        return new DiaryEntryComment(diaryEntryId, authorId, content, createdAt);
    }

    void reviseBy(long actorId, DiaryCommentContent replacement, Instant revisedAt) {
        requireAuthor(actorId);
        DiaryCommentContent requestedContent = Objects.requireNonNull(replacement, "replacement");
        Instant requested = Objects.requireNonNull(revisedAt, "revisedAt");
        content = requestedContent.value();
        updatedAt = requested.isBefore(createdAt) ? createdAt : requested;
    }

    void requireDeletionBy(long actorId) {
        requireAuthor(actorId);
    }

    private void requireAuthor(long actorId) {
        if (actorId != authorId) {
            throw new DiaryMutationForbiddenException();
        }
    }
}
