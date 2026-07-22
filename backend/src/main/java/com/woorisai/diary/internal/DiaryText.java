package com.woorisai.diary.internal;

final class DiaryText {

    private DiaryText() {}

    static String required(String value, int maximumCodePoints) {
        if (value == null || !isValidDatabaseText(value)) {
            throw new InvalidDiaryRequestException();
        }
        String normalized = value.strip();
        int length = normalized.codePointCount(0, normalized.length());
        if (length == 0 || length > maximumCodePoints) {
            throw new InvalidDiaryRequestException();
        }
        return normalized;
    }

    private static boolean isValidDatabaseText(String value) {
        return value.codePoints().noneMatch(codePoint -> codePoint == 0
                || (codePoint >= Character.MIN_SURROGATE
                        && codePoint <= Character.MAX_SURROGATE));
    }
}
