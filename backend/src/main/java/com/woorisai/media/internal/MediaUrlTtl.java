package com.woorisai.media.internal;

import java.util.function.Supplier;

final class MediaUrlTtl {

    private static final int MINIMUM_SECONDS = 60;
    private static final int MAXIMUM_SECONDS = 3_600;

    private MediaUrlTtl() {}

    static int requireSeconds(
            Integer seconds,
            Supplier<? extends RuntimeException> failure) {
        if (seconds == null || seconds < MINIMUM_SECONDS || seconds > MAXIMUM_SECONDS) {
            throw failure.get();
        }
        return seconds;
    }
}
