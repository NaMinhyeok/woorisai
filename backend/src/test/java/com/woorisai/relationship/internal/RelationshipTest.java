package com.woorisai.relationship.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantReference;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;

class RelationshipTest {

    private static final Instant NOW = Instant.parse("2026-07-21T00:00:00Z");
    private static final ParticipantReference SLOT_ONE =
            new ParticipantReference(1, 1, "First");
    private static final ParticipantReference SLOT_TWO =
            new ParticipantReference(2, 2, "Second");
    private static final CanonicalParticipantPair PAIR =
            new CanonicalParticipantPair(SLOT_ONE, SLOT_TWO);

    @Test
    void orientsScoresSoOutgoingBelongsToTheActor() {
        Relationship relationship = relationshipFor(SLOT_ONE.id());

        assertThat(relationship.self()).isEqualTo(SLOT_ONE);
        assertThat(relationship.partner()).isEqualTo(SLOT_TWO);
        assertThat(relationship.outgoing().getId()).isEqualTo(10L);
        assertThat(relationship.incoming().getId()).isEqualTo(11L);
    }

    @Test
    void reversesOutgoingAndIncomingForThePartner() {
        Relationship relationship = relationshipFor(SLOT_TWO.id());

        assertThat(relationship.self()).isEqualTo(SLOT_TWO);
        assertThat(relationship.outgoing().getId()).isEqualTo(11L);
        assertThat(relationship.incoming().getId()).isEqualTo(10L);
    }

    @Test
    void rejectsAnActorOutsideTheCanonicalPair() {
        assertThatThrownBy(() -> Relationship.of(999L, PAIR, scores()))
                .isInstanceOf(RelationshipForbiddenException.class);
    }

    @Test
    void reportsAnIncompleteScorePairAsUnavailableRatherThanLeakingTheOrientationFailure() {
        List<RelationshipScore> onlyOutgoing = List.of(score(10, 1, 2, 50));

        assertThatThrownBy(() -> Relationship.of(SLOT_ONE.id(), PAIR, onlyOutgoing))
                .isInstanceOf(RelationshipUnavailableException.class)
                .hasCauseInstanceOf(RelationshipScorePairUnavailableException.class);
    }

    @Test
    void resolvesTheScoreThatOwnsAChange() {
        Relationship relationship = relationshipFor(SLOT_ONE.id());
        ScoreChange change = relationship.outgoing()
                .change(ScoreChangeIntent.from(10, null), null, NOW);

        assertThat(relationship.scoreOf(change)).isEqualTo(relationship.outgoing());
    }

    @Test
    void rejectsAChangeBelongingToAForeignScore() {
        Relationship relationship = relationshipFor(SLOT_ONE.id());
        RelationshipScore foreign = score(99, 1, 2, 50);
        ScoreChange foreignChange = foreign.change(ScoreChangeIntent.from(1, null), null, NOW);

        assertThatThrownBy(() -> relationship.scoreOf(foreignChange))
                .isInstanceOf(RelationshipUnavailableException.class);
    }

    @Test
    void tellsTheActorApartFromThePartner() {
        Relationship relationship = relationshipFor(SLOT_ONE.id());

        assertThat(relationship.isSelf(SLOT_ONE.id())).isTrue();
        assertThat(relationship.isSelf(SLOT_TWO.id())).isFalse();
    }

    @Test
    void resolvesBothParticipantsAndRejectsAnyoneElse() {
        Relationship relationship = relationshipFor(SLOT_ONE.id());

        assertThat(relationship.participantById(SLOT_TWO.id())).isEqualTo(SLOT_TWO);
        assertThatThrownBy(() -> relationship.participantById(999L))
                .isInstanceOf(RelationshipUnavailableException.class);
    }

    @Test
    void exposesBothScoreIdsForHistoryLookups() {
        Relationship relationship = relationshipFor(SLOT_ONE.id());

        assertThat(relationship.scoreIds()).containsExactlyInAnyOrder(10L, 11L);
    }

    private static Relationship relationshipFor(long actorId) {
        return Relationship.of(actorId, PAIR, scores());
    }

    private static List<RelationshipScore> scores() {
        return List.of(score(10, 1, 2, 50), score(11, 2, 1, 70));
    }

    private static RelationshipScore score(long id, long source, long target, int current) {
        return new RelationshipScore(id, source, target, current, NOW);
    }
}
