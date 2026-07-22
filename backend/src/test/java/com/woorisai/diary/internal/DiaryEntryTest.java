package com.woorisai.diary.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;
import java.util.Optional;
import org.junit.jupiter.api.Test;

class DiaryEntryTest {

    private static final long AUTHOR_ID = 3_000_000_001L;
    private static final long PARTNER_ID = 3_000_000_002L;
    private static final Instant CREATED_AT = Instant.parse("2026-07-21T00:00:00Z");

    @Test
    void authorRevisesContentWhileCreationMetadataRemainsStable() {
        DiaryEntry entry = DiaryEntry.create(
                AUTHOR_ID, DiaryEntryContent.from(" original "), CREATED_AT);
        Instant revisedAt = CREATED_AT.plusSeconds(1);

        entry.reviseBy(
                AUTHOR_ID,
                Optional.of(DiaryEntryContent.from(" changed ")),
                revisedAt);

        assertThat(entry.getAuthorId()).isEqualTo(AUTHOR_ID);
        assertThat(entry.getContent()).isEqualTo("changed");
        assertThat(entry.getCreatedAt()).isEqualTo(CREATED_AT);
        assertThat(entry.getUpdatedAt()).isEqualTo(revisedAt);
    }

    @Test
    void mediaOnlyRevisionTouchesEntryAndClampsTimeToCreation() {
        DiaryEntry entry = DiaryEntry.create(
                AUTHOR_ID, DiaryEntryContent.from("original"), CREATED_AT);

        entry.reviseBy(AUTHOR_ID, Optional.empty(), CREATED_AT.minusSeconds(1));

        assertThat(entry.getContent()).isEqualTo("original");
        assertThat(entry.getUpdatedAt()).isEqualTo(CREATED_AT);
    }

    @Test
    void nonAuthorCannotReviseOrDeleteAndFailedRevisionDoesNotMutate() {
        DiaryEntry entry = DiaryEntry.create(
                AUTHOR_ID, DiaryEntryContent.from("original"), CREATED_AT);

        assertThatThrownBy(() -> entry.reviseBy(
                        PARTNER_ID,
                        Optional.of(DiaryEntryContent.from("forbidden")),
                        CREATED_AT.plusSeconds(1)))
                .isInstanceOf(DiaryMutationForbiddenException.class);
        assertThatThrownBy(() -> entry.requireDeletionBy(PARTNER_ID))
                .isInstanceOf(DiaryMutationForbiddenException.class);
        assertThat(entry.getContent()).isEqualTo("original");
        assertThat(entry.getUpdatedAt()).isNull();

        entry.requireDeletionBy(AUTHOR_ID);
    }

    @Test
    void invalidRevisionArgumentsDoNotPartiallyMutateTheEntry() {
        DiaryEntry entry = DiaryEntry.create(
                AUTHOR_ID, DiaryEntryContent.from("original"), CREATED_AT);

        assertThatThrownBy(() -> entry.reviseBy(
                        AUTHOR_ID,
                        Optional.of(DiaryEntryContent.from("changed")),
                        null))
                .isInstanceOf(NullPointerException.class);

        assertThat(entry.getContent()).isEqualTo("original");
        assertThat(entry.getUpdatedAt()).isNull();
    }

    @Test
    void factoryRejectsInvalidMandatoryState() {
        assertThatThrownBy(() -> DiaryEntry.create(
                        0, DiaryEntryContent.from("entry"), CREATED_AT))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> DiaryEntry.create(AUTHOR_ID, null, CREATED_AT))
                .isInstanceOf(NullPointerException.class);
        assertThatThrownBy(() -> DiaryEntry.create(
                        AUTHOR_ID, DiaryEntryContent.from("entry"), null))
                .isInstanceOf(NullPointerException.class);
    }
}
