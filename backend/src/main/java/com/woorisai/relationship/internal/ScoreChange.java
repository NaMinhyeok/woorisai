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
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

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

    @JdbcTypeCode(SqlTypes.SMALLINT)
    @Column(name = "delta", nullable = false)
    private int delta;

    @JdbcTypeCode(SqlTypes.SMALLINT)
    @Column(name = "resulting_score", nullable = false)
    private int resultingScore;

    @Column(name = "reason", length = 200)
    private String reason;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    ScoreChange(
            long relationshipScoreId,
            long changedById,
            int delta,
            int resultingScore,
            String reason,
            Instant createdAt) {
        if (relationshipScoreId <= 0
                || changedById <= 0
                || delta < -100
                || delta > 100
                || delta == 0
                || resultingScore < 0
                || resultingScore > 100
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
