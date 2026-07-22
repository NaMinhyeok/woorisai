package com.woorisai.relationship;

public record ScoreChangeCommentCreated(long recipientParticipantId, long scoreChangeId) {

    public ScoreChangeCommentCreated {
        if (recipientParticipantId <= 0 || scoreChangeId <= 0) {
            throw new IllegalArgumentException("Score comment event identifiers must be positive");
        }
    }

}
