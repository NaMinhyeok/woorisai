package com.woorisai.participant.internal;

import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantDirectory.ParticipantPairUnavailableException;
import com.woorisai.participant.ParticipantReference;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
class ParticipantDirectoryService implements ParticipantDirectory {

    private final ParticipantRepository participants;

    @Override
    public CanonicalParticipantPair canonicalPair() {
        List<Participant> pair = participants.findAllByOrderBySlotAsc();
        if (pair.size() != 2) {
            throw new ParticipantPairUnavailableException();
        }
        Participant slotOne = pair.get(0);
        Participant slotTwo = pair.get(1);
        if (slotOne == null
                || slotTwo == null
                || slotOne.getId() == null
                || slotTwo.getId() == null) {
            throw new ParticipantPairUnavailableException();
        }
        try {
            return new CanonicalParticipantPair(
                    reference(slotOne),
                    reference(slotTwo));
        } catch (IllegalArgumentException exception) {
            throw new ParticipantPairUnavailableException(exception);
        }
    }

    private ParticipantReference reference(Participant participant) {
        return new ParticipantReference(
                participant.getId(),
                participant.getSlot(),
                participant.getDisplayName());
    }
}
