package com.woorisai.participant;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class CanonicalParticipantPairTest {

    private static final ParticipantReference FIRST =
            new ParticipantReference(1, 1, "First");
    private static final ParticipantReference SECOND =
            new ParticipantReference(2, 2, "Second");

    @Test
    void ownsCanonicalOrderLookupAndPartnerSelection() {
        CanonicalParticipantPair pair = new CanonicalParticipantPair(FIRST, SECOND);

        assertThat(pair.inSlotOrder()).containsExactly(FIRST, SECOND);
        assertThat(pair.participantAtSlot(1)).isEqualTo(FIRST);
        assertThat(pair.participantAtSlot(2)).isEqualTo(SECOND);
        assertThat(pair.findById(1)).contains(FIRST);
        assertThat(pair.matching(new ParticipantReference(1, 1, "Current Name")))
                .contains(FIRST);
        assertThat(pair.partnerOf(1)).contains(SECOND);
        assertThat(pair.partnerOf(2)).contains(FIRST);
        assertThat(pair.findById(3)).isEmpty();
        assertThat(pair.partnerOf(3)).isEmpty();
        assertThat(pair.matching(null)).isEmpty();
        assertThat(pair.matching(new ParticipantReference(1, 2, "Wrong slot"))).isEmpty();
        assertThatThrownBy(() -> pair.participantAtSlot(0))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void rejectsInvalidReferencesAndPairShapes() {
        assertThatThrownBy(() -> new ParticipantReference(0, 1, "First"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new ParticipantReference(1, 3, "First"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new ParticipantReference(1, 1, " "))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new CanonicalParticipantPair(SECOND, FIRST))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new CanonicalParticipantPair(
                        FIRST,
                        new ParticipantReference(1, 2, "Same")))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new CanonicalParticipantPair(FIRST, null))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
