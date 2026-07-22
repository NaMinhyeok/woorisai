package com.woorisai.relationship.internal;

final class RelationshipText {

    private RelationshipText() {}

    static String optional(String value, int maximumCodePoints) {
        if (value == null) {
            return null;
        }
        if (!isValidDatabaseText(value)) {
            throw new InvalidRelationshipRequestException();
        }
        String normalized = value.strip();
        if (normalized.codePointCount(0, normalized.length()) > maximumCodePoints) {
            throw new InvalidRelationshipRequestException();
        }
        return normalized.isEmpty() ? null : normalized;
    }

    static String requireNormalizedOptional(String value, int maximumCodePoints) {
        if (value == null) {
            return null;
        }
        String normalized = value.strip();
        if (!isValidDatabaseText(value)
                || normalized.isEmpty()
                || !normalized.equals(value)
                || value.codePointCount(0, value.length()) > maximumCodePoints) {
            throw new IllegalArgumentException("Relationship text is invalid");
        }
        return value;
    }

    private static boolean isValidDatabaseText(String value) {
        return value.codePoints().noneMatch(codePoint -> codePoint == 0
                || (codePoint >= Character.MIN_SURROGATE
                        && codePoint <= Character.MAX_SURROGATE));
    }
}
