package com.woorisai.diary.internal;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.participant.ParticipantReference;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * Pins the published response contracts that the shared entry/comment shape does not carry.
 *
 * <p>{@code DiaryEntryUpdatedResponse} and {@code DiaryCommentUpdatedResponse} are separate
 * schemas in {@code contracts/openapi-v2.yaml} precisely because a revision promises more than a
 * read does: only the author can revise, and the revision sets a timestamp. These tests keep the
 * records from silently widening back to the read shape.
 */
class DiaryApiModelsTest {

    private static final ParticipantReference AUTHOR =
            new ParticipantReference(1_001L, 1, "author");
    private static final ParticipantReference PARTNER =
            new ParticipantReference(1_002L, 2, "partner");
    private static final Instant CREATED_AT = Instant.parse("2026-07-21T00:00:00Z");
    private static final Instant UPDATED_AT = Instant.parse("2026-07-21T01:00:00Z");

    @Nested
    class ARevisedEntry {

        @Test
        void carriesTheRevisionTimestampThePublishedSchemaRequires() {
            assertThatThrownBy(() -> updatedEntry(mine(), null))
                    .isInstanceOf(IllegalArgumentException.class);

            assertThatCode(() -> updatedEntry(mine(), UPDATED_AT)).doesNotThrowAnyException();
        }

        @Test
        void belongsToTheParticipantWhoRevisedIt() {
            assertThatThrownBy(() -> updatedEntry(theirs(), UPDATED_AT))
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }

    @Nested
    class ARevisedComment {

        @Test
        void carriesTheRevisionTimestampThePublishedSchemaRequires() {
            assertThatThrownBy(() -> updatedComment(mine(), null))
                    .isInstanceOf(IllegalArgumentException.class);

            assertThatCode(() -> updatedComment(mine(), UPDATED_AT)).doesNotThrowAnyException();
        }

        @Test
        void belongsToTheParticipantWhoRevisedIt() {
            assertThatThrownBy(() -> updatedComment(theirs(), UPDATED_AT))
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }

    // A read may show either participant's writing and an unrevised item, so the shared shape
    // accepts both. Losing that would make the list and detail responses unrepresentable.
    @Nested
    class AReadEntryOrComment {

        @Test
        void acceptsThePartnersWritingAndAnUnrevisedItem() {
            assertThatCode(() -> new DiaryEntryResponse(
                    1L, DiaryParticipantResponse.from(PARTNER), "content",
                    CREATED_AT, null, false, List.of(), 0))
                    .doesNotThrowAnyException();

            assertThatCode(() -> new DiaryCommentResponse(
                    1L, DiaryParticipantResponse.from(PARTNER), "content",
                    CREATED_AT, null, false))
                    .doesNotThrowAnyException();
        }
    }

    private static DiaryAuthorship mine() {
        return DiaryAuthorship.of(AUTHOR, AUTHOR);
    }

    private static DiaryAuthorship theirs() {
        return DiaryAuthorship.of(PARTNER, AUTHOR);
    }

    private static DiaryEntryUpdatedResponse updatedEntry(
            DiaryAuthorship authorship, Instant updatedAt) {
        return new DiaryEntryUpdatedResponse(
                1L, authorship.author(), "content", CREATED_AT, updatedAt,
                authorship.isMine(), List.of(), 0);
    }

    private static DiaryCommentUpdatedResponse updatedComment(
            DiaryAuthorship authorship, Instant updatedAt) {
        return new DiaryCommentUpdatedResponse(
                1L, authorship.author(), "content", CREATED_AT, updatedAt, authorship.isMine());
    }
}
