package com.woorisai.diary.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;
import org.junit.jupiter.api.Test;

class DiaryEntryCommentTest {

    private static final long ENTRY_ID = 41;
    private static final long AUTHOR_ID = 3_000_000_001L;
    private static final long PARTNER_ID = 3_000_000_002L;
    private static final Instant CREATED_AT = Instant.parse("2026-07-21T00:00:00Z");

    @Test
    void authorRevisesCommentAndTimeCannotPrecedeCreation() {
        DiaryEntryComment comment = DiaryEntryComment.create(
                ENTRY_ID,
                AUTHOR_ID,
                DiaryCommentContent.from(" original "),
                CREATED_AT);

        comment.reviseBy(
                AUTHOR_ID,
                DiaryCommentContent.from(" changed "),
                CREATED_AT.minusSeconds(1));

        assertThat(comment.getDiaryEntryId()).isEqualTo(ENTRY_ID);
        assertThat(comment.getAuthorId()).isEqualTo(AUTHOR_ID);
        assertThat(comment.getContent()).isEqualTo("changed");
        assertThat(comment.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(comment.getUpdatedAt()).isEqualTo(CREATED_AT);
    }

    @Test
    void nonAuthorCannotReviseOrDeleteAndFailedRevisionDoesNotMutate() {
        DiaryEntryComment comment = DiaryEntryComment.create(
                ENTRY_ID,
                AUTHOR_ID,
                DiaryCommentContent.from("original"),
                CREATED_AT);

        assertThatThrownBy(() -> comment.reviseBy(
                        PARTNER_ID,
                        DiaryCommentContent.from("forbidden"),
                        CREATED_AT.plusSeconds(1)))
                .isInstanceOf(DiaryMutationForbiddenException.class);
        assertThatThrownBy(() -> comment.requireDeletionBy(PARTNER_ID))
                .isInstanceOf(DiaryMutationForbiddenException.class);
        assertThat(comment.getContent()).isEqualTo("original");
        assertThat(comment.getUpdatedAt()).isNull();

        comment.requireDeletionBy(AUTHOR_ID);
    }

    @Test
    void invalidRevisionArgumentsDoNotPartiallyMutateTheComment() {
        DiaryEntryComment comment = DiaryEntryComment.create(
                ENTRY_ID,
                AUTHOR_ID,
                DiaryCommentContent.from("original"),
                CREATED_AT);

        assertThatThrownBy(() -> comment.reviseBy(
                        AUTHOR_ID,
                        DiaryCommentContent.from("changed"),
                        null))
                .isInstanceOf(NullPointerException.class);

        assertThat(comment.getContent()).isEqualTo("original");
        assertThat(comment.getUpdatedAt()).isNull();
    }

    @Test
    void factoryRejectsInvalidMandatoryState() {
        assertThatThrownBy(() -> DiaryEntryComment.create(
                        0,
                        AUTHOR_ID,
                        DiaryCommentContent.from("comment"),
                        CREATED_AT))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> DiaryEntryComment.create(
                        ENTRY_ID,
                        0,
                        DiaryCommentContent.from("comment"),
                        CREATED_AT))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> DiaryEntryComment.create(
                        ENTRY_ID, AUTHOR_ID, null, CREATED_AT))
                .isInstanceOf(NullPointerException.class);
        assertThatThrownBy(() -> DiaryEntryComment.create(
                        ENTRY_ID,
                        AUTHOR_ID,
                        DiaryCommentContent.from("comment"),
                        null))
                .isInstanceOf(NullPointerException.class);
    }
}
