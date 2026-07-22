package com.woorisai.participant;

public interface ParticipantDirectory {

    CanonicalParticipantPair canonicalPair();

    final class ParticipantPairUnavailableException extends RuntimeException {

        public ParticipantPairUnavailableException() {
            super("Participant pair is not available");
        }

        public ParticipantPairUnavailableException(Throwable cause) {
            super("Participant pair is not available", cause);
        }
    }
}
