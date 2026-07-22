package com.woorisai.participant;

public record ParticipantReference(long id, int slot, String displayName) {

    public ParticipantReference {
        if (id <= 0
                || (slot != 1 && slot != 2)
                || displayName == null
                || displayName.isBlank()
                || displayName.codePointCount(0, displayName.length()) > 30) {
            throw new IllegalArgumentException("Participant reference is invalid");
        }
    }
}
