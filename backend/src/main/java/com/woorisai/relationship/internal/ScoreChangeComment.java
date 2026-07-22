package com.woorisai.relationship.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.Immutable;

@Entity
@Immutable
@Getter(AccessLevel.PACKAGE)
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Table(name = "score_change_comment")
class ScoreChangeComment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id", nullable = false)
    private Long id;

    @Column(name = "score_change_id", nullable = false)
    private long scoreChangeId;

    @Column(name = "author_id", nullable = false)
    private long authorId;

    @Column(name = "content", length = 500)
    private String content;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    ScoreChangeComment(long scoreChangeId, long authorId, String content, Instant createdAt) {
        if (scoreChangeId <= 0 || authorId <= 0 || createdAt == null) {
            throw new IllegalArgumentException("Score change comment is invalid");
        }
        this.scoreChangeId = scoreChangeId;
        this.authorId = authorId;
        this.content = RelationshipText.requireNormalizedOptional(content, 500);
        this.createdAt = createdAt;
    }
}
