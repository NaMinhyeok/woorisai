package com.woorisai.identity.internal;

import com.woorisai.participant.ParticipantReference;

record LoginParticipantOption(int participantSlot, String displayName) {

    static LoginParticipantOption from(ParticipantReference participant) {
        return new LoginParticipantOption(
                participant.slot(),
                participant.displayName());
    }
}
