package com.woorisai.identity.internal;

import com.woorisai.participant.ParticipantReference;
import java.io.Serial;
import java.util.List;
import java.util.Objects;
import org.springframework.security.authentication.AbstractAuthenticationToken;

final class ParticipantAuthentication extends AbstractAuthenticationToken {

    @Serial
    private static final long serialVersionUID = 1L;

    private final ParticipantReference participant;

    ParticipantAuthentication(ParticipantReference participant) {
        super(List.of());
        this.participant = Objects.requireNonNull(participant, "Participant is required");
        super.setAuthenticated(true);
    }

    @Override
    public Long getPrincipal() {
        return participant.id();
    }

    @Override
    public Object getCredentials() {
        return null;
    }

    @Override
    public String getName() {
        return Integer.toString(participant.slot());
    }

    @Override
    public void setAuthenticated(boolean authenticated) {
        if (authenticated) {
            throw new IllegalArgumentException("Use the authenticated constructor");
        }
        super.setAuthenticated(false);
    }
}
