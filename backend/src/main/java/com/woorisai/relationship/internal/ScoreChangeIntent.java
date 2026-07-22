package com.woorisai.relationship.internal;

record ScoreChangeIntent(Kind kind, int value) {

    enum Kind {
        DELTA,
        TARGET_SCORE
    }

    ScoreChangeIntent {
        if (kind == null) {
            throw new InvalidScoreChangeIntentException();
        }
        if (kind == Kind.DELTA && (value < -100 || value > 100 || value == 0)) {
            throw new InvalidScoreChangeIntentException();
        }
        if (kind == Kind.TARGET_SCORE && (value < 0 || value > 100)) {
            throw new InvalidScoreChangeIntentException();
        }
    }

    static ScoreChangeIntent from(Integer delta, Integer targetScore) {
        if ((delta == null) == (targetScore == null)) {
            throw new InvalidScoreChangeIntentException();
        }
        return delta != null
                ? new ScoreChangeIntent(Kind.DELTA, delta)
                : new ScoreChangeIntent(Kind.TARGET_SCORE, targetScore);
    }

    int resultingScoreFrom(int currentScore) {
        return switch (kind) {
            case DELTA -> currentScore + value;
            case TARGET_SCORE -> value;
        };
    }
}

final class InvalidScoreChangeIntentException extends RuntimeException {

    InvalidScoreChangeIntentException() {
        super("Score change intent is invalid");
    }
}
