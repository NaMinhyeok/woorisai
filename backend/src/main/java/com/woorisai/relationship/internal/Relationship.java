package com.woorisai.relationship.internal;

import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantReference;
import java.util.List;
import java.util.Set;

record Relationship(
        ParticipantReference self,
        ParticipantReference partner,
        CanonicalParticipantPair participants,
        RelationshipScorePair scores) {

    static Relationship of(
            long actorId,
            CanonicalParticipantPair participants,
            List<RelationshipScore> scores) {
        ParticipantReference self = participants.findById(actorId)
                .orElseThrow(RelationshipForbiddenException::new);
        ParticipantReference partner = participants.partnerOf(self.id())
                .orElseThrow(RelationshipUnavailableException::new);
        return new Relationship(
                self,
                partner,
                participants,
                orient(self, partner, scores));
    }

    private static RelationshipScorePair orient(
            ParticipantReference self,
            ParticipantReference partner,
            List<RelationshipScore> scores) {
        try {
            return RelationshipScorePair.orient(self.id(), partner.id(), scores);
        } catch (RelationshipScorePairUnavailableException exception) {
            throw new RelationshipUnavailableException(exception);
        }
    }

    RelationshipScore outgoing() {
        return scores.outgoing();
    }

    RelationshipScore incoming() {
        return scores.incoming();
    }

    Set<Long> scoreIds() {
        return scores.ids();
    }

    RelationshipScore scoreOf(ScoreChange change) {
        return scores.findById(change.getRelationshipScoreId())
                .orElseThrow(RelationshipUnavailableException::new);
    }

    ParticipantReference participantById(long participantId) {
        return participants.findById(participantId)
                .orElseThrow(RelationshipUnavailableException::new);
    }

    boolean isSelf(long participantId) {
        return self.id() == participantId;
    }
}
