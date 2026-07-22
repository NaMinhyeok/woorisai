package com.woorisai.relationship.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Getter(AccessLevel.PACKAGE)
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Table(name = "relationship_score")
class RelationshipScore {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id", nullable = false)
    private Long id;

    @Column(name = "source_participant_id", nullable = false, unique = true)
    private long sourceParticipantId;

    @Column(name = "target_participant_id", nullable = false, unique = true)
    private long targetParticipantId;

    @JdbcTypeCode(SqlTypes.SMALLINT)
    @Column(name = "current_score", nullable = false)
    private int currentScore;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(name = "version", nullable = false)
    private long version;

    RelationshipScore(
            long id,
            long sourceParticipantId,
            long targetParticipantId,
            int currentScore,
            Instant updatedAt) {
        if (id <= 0
                || sourceParticipantId <= 0
                || targetParticipantId <= 0
                || sourceParticipantId == targetParticipantId
                || currentScore < 0
                || currentScore > 100
                || updatedAt == null) {
            throw new IllegalArgumentException("Relationship score state is invalid");
        }
        this.id = id;
        this.sourceParticipantId = sourceParticipantId;
        this.targetParticipantId = targetParticipantId;
        this.currentScore = currentScore;
        this.updatedAt = updatedAt;
    }

    ScoreChange change(
            ScoreChangeIntent intent,
            String reason,
            Instant changedAt) {
        if (intent == null || changedAt == null) {
            throw new IllegalArgumentException("Relationship score transition is invalid");
        }
        if (id == null
                || id <= 0
                || sourceParticipantId <= 0
                || targetParticipantId <= 0
                || sourceParticipantId == targetParticipantId
                || currentScore < 0
                || currentScore > 100
                || updatedAt == null) {
            throw new IllegalStateException("Relationship score state is invalid");
        }

        int previousScore = currentScore;
        int resultingScore = intent.resultingScoreFrom(previousScore);
        int delta = resultingScore - previousScore;
        if (delta == 0 || resultingScore < 0 || resultingScore > 100) {
            throw new RelationshipScoreChangeRejectedException();
        }

        ScoreChange recorded = new ScoreChange(
                id,
                sourceParticipantId,
                delta,
                resultingScore,
                reason,
                changedAt);
        currentScore = resultingScore;
        updatedAt = changedAt;
        return recorded;
    }

    boolean hasDirection(long sourceId, long targetId) {
        return sourceParticipantId == sourceId && targetParticipantId == targetId;
    }
}

final class RelationshipScoreChangeRejectedException extends RuntimeException {

    RelationshipScoreChangeRejectedException() {
        super("Relationship score change conflicts with current state");
    }
}
