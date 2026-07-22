package com.woorisai.relationship;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class RelationshipEventContractTest {

    @Test
    void eventsContainOnlyPositiveRoutingIds() {
        RelationshipScoreChanged scoreChanged = new RelationshipScoreChanged(11, 21);
        ScoreChangeCommentCreated commentCreated = new ScoreChangeCommentCreated(12, 22);

        assertThat(scoreChanged.recipientParticipantId()).isEqualTo(11);
        assertThat(scoreChanged.scoreChangeId()).isEqualTo(21);
        assertThat(commentCreated.recipientParticipantId()).isEqualTo(12);
        assertThat(commentCreated.scoreChangeId()).isEqualTo(22);
        assertThatThrownBy(() -> new RelationshipScoreChanged(0, 1))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new ScoreChangeCommentCreated(1, 0))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
