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
import java.util.Optional;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Getter(AccessLevel.PACKAGE)
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Table(name = "diary_entry")
class DiaryEntry {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id", nullable = false)
    private Long id;

    @Column(name = "author_id", nullable = false)
    private long authorId;

    @Column(name = "content", nullable = false, length = 1000)
    private String content;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at")
    private Instant updatedAt;

    @Version
    @Column(name = "version", nullable = false)
    private long version;

    private DiaryEntry(long authorId, DiaryEntryContent content, Instant createdAt) {
        if (authorId <= 0) {
            throw new IllegalArgumentException("Diary entry author is invalid");
        }
        this.authorId = authorId;
        this.content = Objects.requireNonNull(content, "content").value();
        this.createdAt = Objects.requireNonNull(createdAt, "createdAt");
    }

    static DiaryEntry create(long authorId, DiaryEntryContent content, Instant createdAt) {
        return new DiaryEntry(authorId, content, createdAt);
    }

    void reviseBy(
            long actorId,
            Optional<DiaryEntryContent> replacement,
            Instant revisedAt) {
        requireAuthor(actorId);
        Optional<DiaryEntryContent> requestedContent =
                Objects.requireNonNull(replacement, "replacement");
        Instant requested = Objects.requireNonNull(revisedAt, "revisedAt");
        requestedContent.ifPresent(value -> content = value.value());
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
