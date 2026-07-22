package com.woorisai.relationship.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;
import org.junit.jupiter.api.Test;

class RelationshipScoreTest {

    private static final Instant INITIAL_TIME = Instant.parse("2026-07-21T00:00:00Z");
    private static final Instant CHANGED_TIME = Instant.parse("2026-07-21T01:00:00Z");

    @Test
    void appliesADeltaAndCreatesItsImmutableHistoryFromTheSameDecision() {
        RelationshipScore score = scoreAt(50);

        ScoreChange change = score.change(
                ScoreChangeIntent.from(10, null), "because", CHANGED_TIME);

        assertThat(change.getRelationshipScoreId()).isEqualTo(10L);
        assertThat(change.getChangedById()).isEqualTo(1L);
        assertThat(change.getDelta()).isEqualTo(10);
        assertThat(change.getResultingScore()).isEqualTo(60);
        assertThat(change.getReason()).isEqualTo("because");
        assertThat(change.getCreatedAt()).isEqualTo(CHANGED_TIME);
        assertThat(score.getCurrentScore()).isEqualTo(60);
        assertThat(score.getUpdatedAt()).isEqualTo(CHANGED_TIME);
        assertThat(score.hasDirection(1, 2)).isTrue();
    }

    @Test
    void movesToAnAbsoluteTargetAndDerivesItsDelta() {
        RelationshipScore score = scoreAt(50);

        ScoreChange change = score.change(
                ScoreChangeIntent.from(null, 25), null, CHANGED_TIME);

        assertThat(change.getDelta()).isEqualTo(-25);
        assertThat(change.getResultingScore()).isEqualTo(25);
        assertThat(score.getCurrentScore()).isEqualTo(25);
    }

    @Test
    void rejectsMalformedIntentsBeforeTheyReachTheAggregate() {
        assertThatThrownBy(() -> ScoreChangeIntent.from(null, null))
                .isInstanceOf(InvalidScoreChangeIntentException.class);
        assertThatThrownBy(() -> ScoreChangeIntent.from(1, 50))
                .isInstanceOf(InvalidScoreChangeIntentException.class);
        assertThatThrownBy(() -> ScoreChangeIntent.from(0, null))
                .isInstanceOf(InvalidScoreChangeIntentException.class);
        assertThatThrownBy(() -> ScoreChangeIntent.from(101, null))
                .isInstanceOf(InvalidScoreChangeIntentException.class);
        assertThatThrownBy(() -> ScoreChangeIntent.from(null, -1))
                .isInstanceOf(InvalidScoreChangeIntentException.class);
        assertThatThrownBy(() -> ScoreChangeIntent.from(null, 101))
                .isInstanceOf(InvalidScoreChangeIntentException.class);
    }

    @Test
    void rejectsNoOpAndOutOfRangeChangesWithoutMutatingTheScore() {
        RelationshipScore score = scoreAt(50);

        assertThatThrownBy(() -> score.change(
                        ScoreChangeIntent.from(null, 50), null, CHANGED_TIME))
                .isInstanceOf(RelationshipScoreChangeRejectedException.class);
        assertThatThrownBy(() -> score.change(
                        ScoreChangeIntent.from(51, null), null, CHANGED_TIME))
                .isInstanceOf(RelationshipScoreChangeRejectedException.class);
        assertThatThrownBy(() -> score.change(
                        ScoreChangeIntent.from(-51, null), null, CHANGED_TIME))
                .isInstanceOf(RelationshipScoreChangeRejectedException.class);

        assertThat(score.getCurrentScore()).isEqualTo(50);
        assertThat(score.getUpdatedAt()).isEqualTo(INITIAL_TIME);
    }

    @Test
    void allowsTheInclusiveScoreBoundaries() {
        RelationshipScore lower = scoreAt(50);
        RelationshipScore upper = scoreAt(50);

        assertThat(lower.change(ScoreChangeIntent.from(null, 0), null, CHANGED_TIME)
                        .getResultingScore())
                .isEqualTo(0);
        assertThat(upper.change(ScoreChangeIntent.from(null, 100), null, CHANGED_TIME)
                        .getResultingScore())
                .isEqualTo(100);
    }

    @Test
    void rejectsNonCanonicalHistoryTextWithoutMutatingTheScore() {
        RelationshipScore score = scoreAt(50);

        assertThatThrownBy(() -> score.change(
                        ScoreChangeIntent.from(1, null), "  reason  ", CHANGED_TIME))
                .isInstanceOf(IllegalArgumentException.class);

        assertThat(score.getCurrentScore()).isEqualTo(50);
        assertThat(score.getUpdatedAt()).isEqualTo(INITIAL_TIME);
    }

    private static RelationshipScore scoreAt(int currentScore) {
        return new RelationshipScore(10, 1, 2, currentScore, INITIAL_TIME);
    }
}
