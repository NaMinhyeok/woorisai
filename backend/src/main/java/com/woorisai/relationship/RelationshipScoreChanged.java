package com.woorisai.relationship;

public record RelationshipScoreChanged(long recipientParticipantId, long scoreChangeId) {

    public RelationshipScoreChanged {
        if (recipientParticipantId <= 0 || scoreChangeId <= 0) {
            throw new IllegalArgumentException("Relationship score event identifiers must be positive");
        }
    }

}
