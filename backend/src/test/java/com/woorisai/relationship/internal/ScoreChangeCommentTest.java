package com.woorisai.relationship.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;
import org.junit.jupiter.api.Test;

class ScoreChangeCommentTest {

    private static final Instant NOW = Instant.parse("2026-07-21T00:00:00Z");

    @Test
    void ownsItsPersistedScalarInvariants() {
        ScoreChangeComment comment = new ScoreChangeComment(10, 1, "content", NOW);

        assertThat(comment.getScoreChangeId()).isEqualTo(10);
        assertThat(comment.getAuthorId()).isEqualTo(1);
        assertThat(comment.getContent()).isEqualTo("content");
        assertThat(comment.getCreatedAt()).isEqualTo(NOW);
    }

    @Test
    void rejectsInvalidIdentityTimeAndNonCanonicalText() {
        assertThatThrownBy(() -> new ScoreChangeComment(0, 1, "content", NOW))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new ScoreChangeComment(10, 0, "content", NOW))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new ScoreChangeComment(10, 1, "content", null))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new ScoreChangeComment(10, 1, "  content  ", NOW))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new ScoreChangeComment(10, 1, "", NOW))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
