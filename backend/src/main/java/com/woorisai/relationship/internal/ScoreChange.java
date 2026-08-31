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
@Table(name = "score_change")
class ScoreChange {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id", nullable = false)
    private Long id;

    @Column(name = "relationship_score_id", nullable = false)
    private long relationshipScoreId;

    @Column(name = "changed_by_id", nullable = false)
    private long changedById;

    @Column(name = "delta", nullable = false)
    private long delta;

    @Column(name = "resulting_score", nullable = false)
    private long resultingScore;

    @Column(name = "reason", length = 200)
    private String reason;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    ScoreChange(
            long relationshipScoreId,
            long changedById,
            long delta,
            long resultingScore,
            String reason,
            Instant createdAt) {
        if (relationshipScoreId <= 0
                || changedById <= 0
                || delta == 0
                || resultingScore < 0
                || createdAt == null) {
            throw new IllegalArgumentException("Recorded score change is invalid");
        }
        this.relationshipScoreId = relationshipScoreId;
        this.changedById = changedById;
        this.delta = delta;
        this.resultingScore = resultingScore;
        this.reason = RelationshipText.requireNormalizedOptional(reason, 200);
        this.createdAt = createdAt;
    }
}
