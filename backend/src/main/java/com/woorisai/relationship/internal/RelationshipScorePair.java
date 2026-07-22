package com.woorisai.relationship.internal;

import java.util.List;
import java.util.Optional;
import java.util.Set;

record RelationshipScorePair(
        RelationshipScore outgoing,
        RelationshipScore incoming) {

    static RelationshipScorePair orient(
            long selfId,
            long partnerId,
            List<RelationshipScore> scores) {
        if (scores == null || scores.size() != 2) {
            throw new RelationshipScorePairUnavailableException();
        }
        RelationshipScore outgoing = scores.stream()
                .filter(score -> score != null && score.hasDirection(selfId, partnerId))
                .findFirst()
                .orElseThrow(RelationshipScorePairUnavailableException::new);
        RelationshipScore incoming = scores.stream()
                .filter(score -> score != null && score.hasDirection(partnerId, selfId))
                .findFirst()
                .orElseThrow(RelationshipScorePairUnavailableException::new);
        return new RelationshipScorePair(outgoing, incoming);
    }

    RelationshipScorePair {
        if (outgoing == null
                || incoming == null
                || outgoing == incoming
                || outgoing.getId() == null
                || incoming.getId() == null
                || outgoing.getId() <= 0
                || incoming.getId() <= 0
                || outgoing.getId().equals(incoming.getId())
                || outgoing.getSourceParticipantId() != incoming.getTargetParticipantId()
                || outgoing.getTargetParticipantId() != incoming.getSourceParticipantId()) {
            throw new RelationshipScorePairUnavailableException();
        }
    }

    Set<Long> ids() {
        return Set.of(outgoing.getId(), incoming.getId());
    }

    Optional<RelationshipScore> findById(long scoreId) {
        if (outgoing.getId() == scoreId) {
            return Optional.of(outgoing);
        }
        if (incoming.getId() == scoreId) {
            return Optional.of(incoming);
        }
        return Optional.empty();
    }
}

final class RelationshipScorePairUnavailableException extends RuntimeException {

    RelationshipScorePairUnavailableException() {
        super("Directional relationship score pair is unavailable");
    }
}
