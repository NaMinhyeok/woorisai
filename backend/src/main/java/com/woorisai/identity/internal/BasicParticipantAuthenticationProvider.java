package com.woorisai.identity.internal;

import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantDirectory.ParticipantPairUnavailableException;
import com.woorisai.participant.ParticipantReference;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataAccessException;
import org.springframework.security.authentication.AuthenticationProvider;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.InternalAuthenticationServiceException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.TransactionException;

@Component
@RequiredArgsConstructor
class BasicParticipantAuthenticationProvider implements AuthenticationProvider {

    private static final String INVALID_CREDENTIALS = "Invalid participant credentials";
    private static final String AUTHENTICATION_UNAVAILABLE = "Authentication is unavailable";
    private static final Pattern BCRYPT_PIN_HASH = Pattern.compile(
            "\\A\\{bcrypt\\}\\$2[ayb]?\\$\\d{2}\\$[./A-Za-z0-9]{53}\\z");

    private final ParticipantDirectory participants;
    private final ParticipantCredentialRepository credentials;
    private final PasswordEncoder passwordEncoder;

    @Override
    public Authentication authenticate(Authentication authentication)
            throws AuthenticationException {
        int slot = parseSlot(authentication.getName());
        String pin = parsePin(authentication.getCredentials());

        try {
            ParticipantReference participant = participants.canonicalPair()
                    .participantAtSlot(slot);
            ParticipantCredential credential = credentials.findById(participant.id())
                    .orElseThrow(BasicParticipantAuthenticationProvider::unavailable);
            if (!matches(pin, credential.getPinHash())) {
                throw invalidCredentials();
            }
            return new ParticipantAuthentication(participant);
        } catch (BadCredentialsException | InternalAuthenticationServiceException exception) {
            throw exception;
        } catch (ParticipantPairUnavailableException
                | DataAccessException
                | TransactionException exception) {
            throw unavailable(exception);
        }
    }

    @Override
    public boolean supports(Class<?> authentication) {
        return UsernamePasswordAuthenticationToken.class.isAssignableFrom(authentication);
    }

    private int parseSlot(String username) {
        if ("1".equals(username)) {
            return 1;
        }
        if ("2".equals(username)) {
            return 2;
        }
        throw invalidCredentials();
    }

    private String parsePin(Object credentials) {
        if (!(credentials instanceof String pin) || !isFourAsciiDigits(pin)) {
            throw invalidCredentials();
        }
        return pin;
    }

    private boolean isFourAsciiDigits(String pin) {
        if (pin.length() != 4) {
            return false;
        }
        for (int index = 0; index < pin.length(); index++) {
            char digit = pin.charAt(index);
            if (digit < '0' || digit > '9') {
                return false;
            }
        }
        return true;
    }

    private boolean matches(String pin, String encodedPin) {
        if (encodedPin == null || !BCRYPT_PIN_HASH.matcher(encodedPin).matches()) {
            throw unavailable();
        }
        try {
            return passwordEncoder.matches(pin, encodedPin);
        } catch (RuntimeException exception) {
            throw unavailable(exception);
        }
    }

    private static BadCredentialsException invalidCredentials() {
        return new BadCredentialsException(INVALID_CREDENTIALS);
    }

    private static InternalAuthenticationServiceException unavailable() {
        return new InternalAuthenticationServiceException(AUTHENTICATION_UNAVAILABLE);
    }

    private static InternalAuthenticationServiceException unavailable(Throwable cause) {
        return new InternalAuthenticationServiceException(
                AUTHENTICATION_UNAVAILABLE,
                cause);
    }
}
