package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class MediaUrlTtlTest {

    @Test
    void acceptsTheInclusiveUrlTtlBoundaries() {
        assertThat(MediaUrlTtl.requireSeconds(60, IllegalStateException::new)).isEqualTo(60);
        assertThat(MediaUrlTtl.requireSeconds(3_600, IllegalStateException::new)).isEqualTo(3_600);
    }

    @Test
    void rejectsMissingAndOutOfRangeTtlsWithTheRequestedFailure() {
        assertRejected(null);
        assertRejected(59);
        assertRejected(3_601);
    }

    private static void assertRejected(Integer seconds) {
        RuntimeException failure = new IllegalStateException("synthetic invalid TTL");
        assertThatThrownBy(() -> MediaUrlTtl.requireSeconds(seconds, () -> failure))
                .isSameAs(failure);
    }
}
