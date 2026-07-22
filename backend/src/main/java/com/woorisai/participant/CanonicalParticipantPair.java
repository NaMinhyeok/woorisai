package com.woorisai.participant;

import java.util.List;
import java.util.Optional;

public record CanonicalParticipantPair(
        ParticipantReference slotOne,
        ParticipantReference slotTwo) {

    public CanonicalParticipantPair {
        if (slotOne == null
                || slotTwo == null
                || slotOne.slot() != 1
                || slotTwo.slot() != 2
                || slotOne.id() == slotTwo.id()) {
            throw new IllegalArgumentException("Canonical participant pair is invalid");
        }
    }

    public List<ParticipantReference> inSlotOrder() {
        return List.of(slotOne, slotTwo);
    }

    public ParticipantReference participantAtSlot(int slot) {
        return switch (slot) {
            case 1 -> slotOne;
            case 2 -> slotTwo;
            default -> throw new IllegalArgumentException("Participant slot is invalid");
        };
    }

    public Optional<ParticipantReference> findById(long participantId) {
        if (slotOne.id() == participantId) {
            return Optional.of(slotOne);
        }
        if (slotTwo.id() == participantId) {
            return Optional.of(slotTwo);
        }
        return Optional.empty();
    }

    public Optional<ParticipantReference> matching(ParticipantReference participant) {
        if (participant == null) {
            return Optional.empty();
        }
        return findById(participant.id())
                .filter(canonical -> canonical.slot() == participant.slot());
    }

    public Optional<ParticipantReference> partnerOf(long participantId) {
        if (slotOne.id() == participantId) {
            return Optional.of(slotTwo);
        }
        if (slotTwo.id() == participantId) {
            return Optional.of(slotOne);
        }
        return Optional.empty();
    }
}
