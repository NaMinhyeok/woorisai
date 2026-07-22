package com.woorisai.relationship.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;

class RelationshipScorePairTest {

    private static final Instant NOW = Instant.parse("2026-07-21T00:00:00Z");

    @Test
    void orientsBothDirectionsRegardlessOfRepositoryOrder() {
        RelationshipScore firstToSecond = score(10, 1, 2, 50);
        RelationshipScore secondToFirst = score(11, 2, 1, 70);

        RelationshipScorePair pair = RelationshipScorePair.orient(
                1, 2, List.of(secondToFirst, firstToSecond));

        assertThat(pair.outgoing()).isSameAs(firstToSecond);
        assertThat(pair.incoming()).isSameAs(secondToFirst);
        assertThat(pair.ids()).containsExactlyInAnyOrder(10L, 11L);
        assertThat(pair.findById(10)).contains(firstToSecond);
    }

    @Test
    void rejectsMissingOrForeignDirections() {
        RelationshipScore firstToSecond = score(10, 1, 2, 50);
        RelationshipScore foreign = score(11, 3, 1, 70);

        assertThatThrownBy(() -> RelationshipScorePair.orient(
                        1, 2, List.of(firstToSecond)))
                .isInstanceOf(RelationshipScorePairUnavailableException.class);
        assertThatThrownBy(() -> RelationshipScorePair.orient(
                        1, 2, List.of(firstToSecond, foreign)))
                .isInstanceOf(RelationshipScorePairUnavailableException.class);
    }

    @Test
    void rejectsAContradictoryPairEvenWhenConstructedDirectly() {
        RelationshipScore firstToSecond = score(10, 1, 2, 50);
        RelationshipScore unrelated = score(11, 3, 4, 70);
        RelationshipScore duplicateId = score(10, 2, 1, 70);

        assertThatThrownBy(() -> new RelationshipScorePair(firstToSecond, unrelated))
                .isInstanceOf(RelationshipScorePairUnavailableException.class);
        assertThatThrownBy(() -> new RelationshipScorePair(firstToSecond, duplicateId))
                .isInstanceOf(RelationshipScorePairUnavailableException.class);
    }

    private static RelationshipScore score(
            long id,
            long source,
            long target,
            int current) {
        return new RelationshipScore(id, source, target, current, NOW);
    }
}
