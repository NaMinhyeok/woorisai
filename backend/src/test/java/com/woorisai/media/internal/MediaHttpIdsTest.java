package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.UUID;
import org.junit.jupiter.api.Test;

class MediaHttpIdsTest {

    @Test
    void acceptsCanonicalUuidsInEitherCase() {
        assertThat(MediaHttpIds.parse("11111111-1111-4111-8111-111111111111", failure()))
                .isEqualTo(UUID.fromString("11111111-1111-4111-8111-111111111111"));
        assertThat(MediaHttpIds.parse("AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE", failure()))
                .isEqualTo(UUID.fromString("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"));
    }

    // UUID.fromString alone widens short groups instead of rejecting them: "1-1-1-1-1" becomes
    // 00000001-0001-0001-0001-000000000001, which addresses a different media object than the
    // caller asked for. The canonical pattern is what keeps that out.
    @Test
    void rejectsAbbreviatedFormsThatUuidFromStringWouldSilentlyWiden() {
        assertRejected("1-1-1-1-1");
        assertRejected("11111111-1111-4111-8111-11111111111");
    }

    @Test
    void rejectsMissingAndMalformedValuesWithTheRequestedFailure() {
        assertRejected(null);
        assertRejected("");
        assertRejected("not-a-uuid");
        assertRejected("0x1-0x1-0x1-1-1");
        assertRejected(" 11111111-1111-4111-8111-111111111111 ");
    }

    private static void assertRejected(String value) {
        RuntimeException failure = new IllegalStateException("synthetic invalid id");
        assertThatThrownBy(() -> MediaHttpIds.parse(value, () -> failure)).isSameAs(failure);
    }

    private static java.util.function.Supplier<RuntimeException> failure() {
        return () -> new IllegalStateException("unexpected rejection");
    }
}
