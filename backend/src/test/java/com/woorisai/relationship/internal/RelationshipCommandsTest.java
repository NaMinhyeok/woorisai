package com.woorisai.relationship.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class RelationshipCommandsTest {

    @Test
    void constructsNormalizedCommandsAtTheWebBoundary() {
        UUID scoreMedia = UUID.randomUUID();
        UUID commentMedia = UUID.randomUUID();

        ChangeScoreCommand change =
                ChangeScoreCommand.from(1, null, "  reason  ", List.of(scoreMedia));
        CreateScoreCommentCommand comment =
                CreateScoreCommentCommand.from("  comment  ", List.of(commentMedia));

        assertThat(change.intent()).isEqualTo(ScoreChangeIntent.from(1, null));
        assertThat(change.reason()).isEqualTo("reason");
        assertThat(change.mediaUploadIds()).containsExactly(scoreMedia);
        assertThat(comment.content()).isEqualTo("comment");
        assertThat(comment.mediaUploadIds()).containsExactly(commentMedia);
    }

    @Test
    void rejectsMalformedScoreAndCommentCommandsBeforeTheService() {
        UUID duplicate = UUID.randomUUID();
        String nul = Character.toString(0);

        assertThatThrownBy(() -> ChangeScoreCommand.from(null, null, null, List.of()))
                .isInstanceOf(InvalidRelationshipRequestException.class);
        assertThatThrownBy(() -> ChangeScoreCommand.from(1, 50, null, List.of()))
                .isInstanceOf(InvalidRelationshipRequestException.class);
        assertThatThrownBy(() -> ChangeScoreCommand.from(0, null, null, List.of()))
                .isInstanceOf(InvalidRelationshipRequestException.class);
        assertThatThrownBy(() -> ChangeScoreCommand.from(null, 101, null, List.of()))
                .isInstanceOf(InvalidRelationshipRequestException.class);
        assertThatThrownBy(() -> ChangeScoreCommand.from(
                        1, null, "bad" + nul + "reason", List.of()))
                .isInstanceOf(InvalidRelationshipRequestException.class);
        assertThatThrownBy(() -> ChangeScoreCommand.from(
                        1, null, null, List.of(duplicate, duplicate)))
                .isInstanceOf(InvalidRelationshipRequestException.class);
        assertThatThrownBy(() -> CreateScoreCommentCommand.from(" ", List.of()))
                .isInstanceOf(InvalidRelationshipRequestException.class);
        assertThatThrownBy(() -> CreateScoreCommentCommand.from(
                        "bad" + nul + "comment", List.of()))
                .isInstanceOf(InvalidRelationshipRequestException.class);
    }
}
