package com.woorisai.testing;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

/**
 * Proves the schema check rejects the drift that hand-picked jsonPath assertions let through.
 *
 * <p>Each case is a body that a {@code jsonPath("$.id").value(41)} style assertion would accept.
 */
class PublishedSchemaTest {

    private static final String VALID_ENTRY = """
            {
              "id": 41,
              "author": {"slot": 1, "displayName": "author"},
              "content": "오늘의 기록",
              "createdAt": "2026-07-21T00:00:00Z",
              "updatedAt": null,
              "isMine": true,
              "attachments": [],
              "commentCount": 0
            }
            """;

    @Test
    void acceptsABodyThatMatchesThePublishedSchema() {
        assertThatCode(() -> PublishedSchema.assertMatches("DiaryEntryResponse", VALID_ENTRY))
                .doesNotThrowAnyException();
    }

    // additionalProperties: false is published on 36 schemas, and the iOS client generates its
    // types from them, so an extra field breaks decoding on the device.
    @Test
    void rejectsAFieldThePublishedSchemaDoesNotDeclare() {
        String withExtraField = VALID_ENTRY.replace(
                "\"commentCount\": 0", "\"commentCount\": 0, \"draft\": true");

        assertThatThrownBy(() -> PublishedSchema.assertMatches("DiaryEntryResponse", withExtraField))
                .isInstanceOf(AssertionError.class)
                .hasMessageContaining("draft");
    }

    @Test
    void rejectsAMissingRequiredField() {
        String withoutCommentCount = VALID_ENTRY.replace(",\n  \"commentCount\": 0", "");

        assertThatThrownBy(() ->
                PublishedSchema.assertMatches("DiaryEntryResponse", withoutCommentCount))
                .isInstanceOf(AssertionError.class)
                .hasMessageContaining("commentCount");
    }

    @Test
    void rejectsAFieldWhoseTypeChanged() {
        String idAsString = VALID_ENTRY.replace("\"id\": 41", "\"id\": \"41\"");

        assertThatThrownBy(() -> PublishedSchema.assertMatches("DiaryEntryResponse", idAsString))
                .isInstanceOf(AssertionError.class);
    }

    // The revised responses pin isMine to true and drop null from updatedAt. A read body is a
    // valid entry yet an invalid revision, which is exactly the distinction the two schemas carry.
    @Test
    void rejectsAReadBodyWhereTheSchemaRequiresARevision() {
        assertThatThrownBy(() ->
                PublishedSchema.assertMatches("DiaryEntryUpdatedResponse", VALID_ENTRY))
                .isInstanceOf(AssertionError.class);
    }

    @Test
    void failsLoudlyWhenTheNamedSchemaIsNotPublished() {
        assertThatThrownBy(() -> PublishedSchema.assertMatches("NoSuchResponse", VALID_ENTRY))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("NoSuchResponse");
    }
}
