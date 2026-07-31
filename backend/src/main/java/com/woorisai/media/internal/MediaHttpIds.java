package com.woorisai.media.internal;

import java.util.UUID;
import java.util.function.Supplier;
import java.util.regex.Pattern;

final class MediaHttpIds {

    // UUID.fromString accepts abbreviated groups and widens them ("1-1-1-1-1" parses as
    // 00000001-0001-0001-0001-000000000001), so a caller could reach a different media object
    // than the one in the request. Only the canonical 8-4-4-4-12 form gets through.
    private static final Pattern CANONICAL_UUID = Pattern.compile(
            "(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");

    private MediaHttpIds() {}

    static UUID parse(String value, Supplier<? extends RuntimeException> failure) {
        if (value == null || !CANONICAL_UUID.matcher(value).matches()) {
            throw failure.get();
        }
        try {
            return UUID.fromString(value);
        } catch (IllegalArgumentException exception) {
            throw failure.get();
        }
    }

    static long requireActor(Long actorId, Supplier<? extends RuntimeException> failure) {
        if (actorId == null || actorId <= 0) {
            throw failure.get();
        }
        return actorId;
    }
}
