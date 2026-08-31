package com.woorisai.relationship.internal;

record ScoreChangeIntent(Kind kind, long value) {

    enum Kind {
        DELTA,
        TARGET_SCORE
    }

    ScoreChangeIntent {
        if (kind == null) {
            throw new InvalidScoreChangeIntentException();
        }
        if (kind == Kind.DELTA && value == 0) {
            throw new InvalidScoreChangeIntentException();
        }
        if (kind == Kind.TARGET_SCORE && value < 0) {
            throw new InvalidScoreChangeIntentException();
        }
    }

    static ScoreChangeIntent from(Long delta, Long targetScore) {
        if ((delta == null) == (targetScore == null)) {
            throw new InvalidScoreChangeIntentException();
        }
        return delta != null
                ? new ScoreChangeIntent(Kind.DELTA, delta)
                : new ScoreChangeIntent(Kind.TARGET_SCORE, targetScore);
    }

    long resultingScoreFrom(long currentScore) {
        return switch (kind) {
            case DELTA -> Math.addExact(currentScore, value);
            case TARGET_SCORE -> value;
        };
    }
}

final class InvalidScoreChangeIntentException extends RuntimeException {

    InvalidScoreChangeIntentException() {
        super("Score change intent is invalid");
    }
}
