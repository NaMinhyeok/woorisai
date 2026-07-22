package com.woorisai.identity.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;

import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantDirectory.ParticipantPairUnavailableException;
import com.woorisai.participant.ParticipantReference;
import java.time.Instant;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.persistence.autoconfigure.EntityScan;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.InternalAuthenticationServiceException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.TestPropertySource;

@SpringBootTest(
        classes = BasicParticipantAuthenticationProviderCleanSchemaTest.TestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@TestPropertySource(
        locations = "classpath:clean-schema-h2.properties",
        properties = {
            "spring.autoconfigure.exclude="
                + "org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration,"
                + "org.springframework.modulith.events.jpa.JpaEventPublicationAutoConfiguration,"
                + "org.springframework.modulith.events.config.EventPublicationAutoConfiguration",
            "spring.datasource.url=jdbc:h2:mem:identity-basic-clean-schema;"
                + "MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;"
                + "DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE"
})
class BasicParticipantAuthenticationProviderCleanSchemaTest {

    private static final long FIRST_ID = 3_000_000_001L;
    private static final long SECOND_ID = 3_000_000_002L;
    private static final ParticipantReference FIRST =
            new ParticipantReference(FIRST_ID, 1, "Fixture One");
    private static final ParticipantReference SECOND =
            new ParticipantReference(SECOND_ID, 2, "Fixture Two");
    private static final CanonicalParticipantPair PAIR =
            new CanonicalParticipantPair(FIRST, SECOND);

    @Autowired
    private BasicParticipantAuthenticationProvider authenticationProvider;

    @Autowired
    private ParticipantCredentialRepository credentials;

    @Autowired
    private MutableParticipantDirectory participants;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private JdbcTemplate jdbc;

    @BeforeEach
    void resetDatabase() {
        jdbc.update("DELETE FROM woorisai.participant_credential");
        jdbc.update("DELETE FROM woorisai.participant");
        insertParticipant(FIRST);
        insertParticipant(SECOND);
        participants.unavailable = false;
    }

    @Test
    void validatesTheCleanJpaMappingAndAuthenticatesTheCanonicalParticipant() {
        String hash = passwordEncoder.encode("0123");
        insertCredential(FIRST_ID, hash);

        ParticipantCredential stored = credentials.findById(FIRST_ID).orElseThrow();
        assertThat(stored.getParticipantId()).isEqualTo(FIRST_ID);
        assertThat(stored.getPinHash()).isEqualTo(hash);
        assertThat(stored.getUpdatedAt())
                .isEqualTo(Instant.parse("2026-07-21T00:00:00Z"));

        ParticipantAuthentication authentication =
                (ParticipantAuthentication) authenticationProvider.authenticate(
                        UsernamePasswordAuthenticationToken.unauthenticated("1", "0123"));

        assertThat(authentication.isAuthenticated()).isTrue();
        assertThat(authentication.getPrincipal()).isEqualTo(FIRST_ID);
        assertThat(authentication.getCredentials()).isNull();
        assertThat(authentication.getAuthorities()).isEmpty();
    }

    @Test
    void rejectsWrongPinAndNonAsciiCredentialSyntaxAsGenericBadCredentials() {
        insertCredential(FIRST_ID, passwordEncoder.encode("0123"));

        assertThatThrownBy(() -> authenticationProvider.authenticate(
                        UsernamePasswordAuthenticationToken.unauthenticated("1", "9999")))
                .isInstanceOf(BadCredentialsException.class)
                .hasMessage("Invalid participant credentials");
        assertThatThrownBy(() -> authenticationProvider.authenticate(
                        UsernamePasswordAuthenticationToken.unauthenticated("1", "１２３４")))
                .isInstanceOf(BadCredentialsException.class)
                .hasMessage("Invalid participant credentials");
        assertThatThrownBy(() -> authenticationProvider.authenticate(
                        UsernamePasswordAuthenticationToken.unauthenticated("3", "0123")))
                .isInstanceOf(BadCredentialsException.class)
                .hasMessage("Invalid participant credentials");
    }

    @Test
    void failsClosedWhenPairProviderCredentialOrStoredHashIsUnavailable() {
        participants.unavailable = true;
        assertUnavailable(() -> authenticationProvider.authenticate(
                UsernamePasswordAuthenticationToken.unauthenticated("1", "0123")));

        participants.unavailable = false;
        assertUnavailable(() -> authenticationProvider.authenticate(
                UsernamePasswordAuthenticationToken.unauthenticated("1", "0123")));

        insertCredential(FIRST_ID, "{bcrypt}malformed");
        assertUnavailable(() -> authenticationProvider.authenticate(
                UsernamePasswordAuthenticationToken.unauthenticated("1", "0123")));
    }

    @Test
    void translatesRepositoryFailureToInternalAuthenticationServiceFailure() {
        ParticipantCredentialRepository failingRepository =
                mock(ParticipantCredentialRepository.class);
        given(failingRepository.findById(FIRST_ID)).willThrow(
                new DataAccessResourceFailureException("fixture database unavailable"));
        BasicParticipantAuthenticationProvider provider =
                new BasicParticipantAuthenticationProvider(
                        participants,
                        failingRepository,
                        passwordEncoder);

        assertUnavailable(() -> provider.authenticate(
                UsernamePasswordAuthenticationToken.unauthenticated("1", "0123")));
    }

    private void assertUnavailable(Runnable authentication) {
        assertThatThrownBy(authentication::run)
                .isInstanceOf(InternalAuthenticationServiceException.class)
                .hasMessage("Authentication is unavailable");
    }

    private void insertParticipant(ParticipantReference participant) {
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, ?, ?, CAST(? AS TIMESTAMP WITH TIME ZONE))
                """,
                participant.id(),
                participant.slot(),
                participant.displayName(),
                "2026-07-21T00:00:00Z");
    }

    private void insertCredential(long participantId, String pinHash) {
        jdbc.update("""
                INSERT INTO woorisai.participant_credential (
                    participant_id, pin_hash, updated_at
                ) VALUES (?, ?, CAST(? AS TIMESTAMP WITH TIME ZONE))
                """,
                participantId,
                pinHash,
                "2026-07-21T00:00:00Z");
    }

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackageClasses = ParticipantCredential.class)
    @EnableJpaRepositories(basePackageClasses = ParticipantCredentialRepository.class)
    @Import({
            BasicParticipantAuthenticationProvider.class,
            IdentityAuthenticationConfiguration.class,
            TestBeans.class
    })
    static class TestApplication {}

    @TestConfiguration(proxyBeanMethods = false)
    static class TestBeans {

        @Bean
        MutableParticipantDirectory participantDirectory() {
            return new MutableParticipantDirectory();
        }
    }

    static final class MutableParticipantDirectory implements ParticipantDirectory {

        private boolean unavailable;

        @Override
        public CanonicalParticipantPair canonicalPair() {
            if (unavailable) {
                throw new ParticipantPairUnavailableException();
            }
            return PAIR;
        }
    }
}
