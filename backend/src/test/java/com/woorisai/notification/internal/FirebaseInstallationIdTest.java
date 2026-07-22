package com.woorisai.notification.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class FirebaseInstallationIdTest {

    private static final String VALUE = "c123456789012345678901";

    @Test
    void acceptsOnlyTheExactAsciiBase64UrlValue() {
        assertThat(FirebaseInstallationId.parse(VALUE).value()).isEqualTo(VALUE);

        for (String invalid : new String[] {
                "too-short",
                "c12345678901234567890!",
                " c123456789012345678901",
                "c123456789012345678901 "
        }) {
            assertThatThrownBy(() -> FirebaseInstallationId.parse(invalid))
                    .isInstanceOf(InvalidNotificationFidException.class);
        }
        assertThatThrownBy(() -> FirebaseInstallationId.parse(null))
                .isInstanceOf(InvalidNotificationFidException.class);
    }

    @Test
    void hasImmutableValueSemantics() {
        FirebaseInstallationId first = FirebaseInstallationId.parse(VALUE);
        FirebaseInstallationId second = FirebaseInstallationId.parse(VALUE);

        assertThat(first).isEqualTo(second);
    }
}
