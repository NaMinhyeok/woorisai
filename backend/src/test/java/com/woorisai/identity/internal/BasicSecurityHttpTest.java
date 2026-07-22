package com.woorisai.identity.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.then;
import static org.mockito.BDDMockito.willThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.woorisai.WoorisaiApplication;
import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantDirectory.ParticipantPairUnavailableException;
import com.woorisai.participant.ParticipantReference;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.CannotCreateTransactionException;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

@WebMvcTest(controllers = {
        LoginOptionsController.class,
        BasicSecurityHttpTest.SecurityProbeController.class
})
@ContextConfiguration(classes = WoorisaiApplication.class)
@Import({
        ApiSecurityConfiguration.class,
        ApiSecurityProblemHandler.class,
        BasicParticipantAuthenticationProvider.class,
        IdentityAuthenticationConfiguration.class,
        LoginOptionsApiExceptionHandler.class,
        BasicSecurityHttpTest.SecurityProbeController.class
})
class BasicSecurityHttpTest {

    private static final long FIRST_ID = 3_000_000_001L;
    private static final ParticipantReference FIRST =
            new ParticipantReference(FIRST_ID, 1, "Fixture One");
    private static final ParticipantReference SECOND =
            new ParticipantReference(3_000_000_002L, 2, "Fixture Two");
    private static final CanonicalParticipantPair PAIR =
            new CanonicalParticipantPair(FIRST, SECOND);

    @Autowired
    private MockMvc mvc;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @MockitoBean
    private ParticipantDirectory participants;

    @MockitoBean
    private ParticipantCredentialRepository credentials;

    @BeforeEach
    void canonicalIdentity() {
        given(participants.canonicalPair()).willReturn(PAIR);
        given(credentials.findById(FIRST_ID)).willReturn(Optional.of(
                new ParticipantCredential(
                        FIRST_ID,
                        passwordEncoder.encode("0123"),
                        Instant.parse("2026-07-21T00:00:00Z"))));
    }

    @Test
    void publicGetEndpointsIgnoreEvenMalformedAuthorization() throws Exception {
        ResultActions health = mvc.perform(get("/health")
                .header(HttpHeaders.AUTHORIZATION, "Basic !!!"));

        expectStateless(health)
                .andExpect(status().isOk())
                .andExpect(content().string("up"));

        ResultActions loginOptions = mvc.perform(get("/api/v2/auth/login-options")
                .header(HttpHeaders.AUTHORIZATION, "Basic !!!"));

        expectStateless(loginOptions)
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.participants[0].participantSlot").value(1))
                .andExpect(jsonPath("$.participants[0].displayName").value("Fixture One"))
                .andExpect(jsonPath("$.participants[1].participantSlot").value(2))
                .andExpect(jsonPath("$.participants[1].displayName").value("Fixture Two"));

        then(credentials).shouldHaveNoInteractions();
    }

    @Test
    void onlyTheExactGetMethodIsPublic() throws Exception {
        expectAuthenticationRequired(mvc.perform(post("/health")));
        expectAuthenticationRequired(mvc.perform(
                post("/api/v2/auth/login-options")));
        expectAuthenticationRequired(mvc.perform(
                get("/api/v2/auth/login-options/")));
    }

    @Test
    void validBasicCredentialsExposeOnlyTheParticipantIdPrincipal() throws Exception {
        ResultActions response = mvc.perform(get("/api/v2/test/principal")
                .header(HttpHeaders.AUTHORIZATION, basic("1", "0123")));

        expectStateless(response)
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.id").value(FIRST_ID));

        then(credentials).should().findById(FIRST_ID);
    }

    @Test
    void malformedSlotAndWrongPinShareTheGenericUnauthorizedProblem() throws Exception {
        expectAuthenticationRequired(mvc.perform(get("/api/v2/test/principal")
                        .header(HttpHeaders.AUTHORIZATION, basic("3", "0123"))))
                .andExpect(content().string(not(containsString("0123"))));

        expectAuthenticationRequired(mvc.perform(get("/api/v2/test/principal")
                        .header(HttpHeaders.AUTHORIZATION, basic("1", "9999"))))
                .andExpect(content().string(not(containsString("9999"))));

        expectAuthenticationRequired(mvc.perform(get("/api/v2/test/principal")
                .header(HttpHeaders.AUTHORIZATION, "Basic !!!")));
    }

    @Test
    void missingCredentialAndDatabaseFailureAreServiceUnavailableWithoutAChallenge()
            throws Exception {
        given(credentials.findById(FIRST_ID)).willReturn(Optional.empty());
        expectAuthenticationUnavailable(mvc.perform(get("/api/v2/test/principal")
                .header(HttpHeaders.AUTHORIZATION, basic("1", "0123"))));

        given(credentials.findById(FIRST_ID)).willThrow(
                new DataAccessResourceFailureException("fixture database unavailable"));
        expectAuthenticationUnavailable(mvc.perform(get("/api/v2/test/principal")
                .header(HttpHeaders.AUTHORIZATION, basic("1", "0123"))));

        willThrow(new CannotCreateTransactionException("fixture transaction unavailable"))
                .given(credentials).findById(FIRST_ID);
        expectAuthenticationUnavailable(mvc.perform(get("/api/v2/test/principal")
                .header(HttpHeaders.AUTHORIZATION, basic("1", "0123"))));
    }

    @Test
    void loginOptionsTransactionFailureIsServiceUnavailableWithoutAChallenge()
            throws Exception {
        given(participants.canonicalPair()).willThrow(
                new CannotCreateTransactionException("fixture transaction unavailable"));

        expectStateless(mvc.perform(get("/api/v2/auth/login-options")))
                .andExpect(status().isServiceUnavailable())
                .andExpect(header().doesNotExist(HttpHeaders.WWW_AUTHENTICATE))
                .andExpect(jsonPath("$.errorCode").value("LOGIN_OPTIONS_UNAVAILABLE"));
    }

    @Test
    void unavailableCanonicalPairAndMalformedStoredHashAreServiceUnavailable() throws Exception {
        given(participants.canonicalPair())
                .willThrow(new ParticipantPairUnavailableException())
                .willReturn(PAIR);
        expectAuthenticationUnavailable(mvc.perform(get("/api/v2/test/principal")
                .header(HttpHeaders.AUTHORIZATION, basic("1", "0123"))));

        given(credentials.findById(FIRST_ID)).willReturn(Optional.of(
                new ParticipantCredential(
                        FIRST_ID,
                        "{bcrypt}malformed",
                        Instant.parse("2026-07-21T00:00:00Z"))));
        expectAuthenticationUnavailable(mvc.perform(get("/api/v2/test/principal")
                .header(HttpHeaders.AUTHORIZATION, basic("1", "0123"))));
    }

    @Test
    void anAuthenticatedParticipantIsDeniedOutsideTheApiWithoutAnotherEndpointLeak()
            throws Exception {
        ResultActions response = mvc.perform(post("/health")
                .header(HttpHeaders.AUTHORIZATION, basic("1", "0123")));

        expectStateless(response)
                .andExpect(status().isForbidden())
                .andExpect(header().doesNotExist(HttpHeaders.WWW_AUTHENTICATE))
                .andExpect(jsonPath("$.errorCode").value("ACCESS_DENIED"));
    }

    private ResultActions expectAuthenticationRequired(ResultActions response)
            throws Exception {
        return expectStateless(response)
                .andExpect(status().isUnauthorized())
                .andExpect(header().string(
                        HttpHeaders.WWW_AUTHENTICATE,
                        "Basic realm=\"woorisai\""))
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Authentication required"))
                .andExpect(jsonPath("$.status").value(401))
                .andExpect(jsonPath("$.detail").value(
                        "Valid HTTP Basic participant credentials are required."))
                .andExpect(jsonPath("$.errorCode").value("AUTHENTICATION_REQUIRED"));
    }

    private ResultActions expectAuthenticationUnavailable(ResultActions response)
            throws Exception {
        return expectStateless(response)
                .andExpect(status().isServiceUnavailable())
                .andExpect(header().doesNotExist(HttpHeaders.WWW_AUTHENTICATE))
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.title").value("Authentication unavailable"))
                .andExpect(jsonPath("$.status").value(503))
                .andExpect(jsonPath("$.detail").value(
                        "Authentication is temporarily unavailable."))
                .andExpect(jsonPath("$.errorCode").value("AUTHENTICATION_UNAVAILABLE"));
    }

    private ResultActions expectStateless(ResultActions response) throws Exception {
        return response
                .andExpect(header().string(
                        HttpHeaders.CACHE_CONTROL,
                        containsString("no-store")))
                .andExpect(header().doesNotExist(HttpHeaders.SET_COOKIE))
                .andExpect(result ->
                        assertThat(result.getRequest().getSession(false)).isNull());
    }

    private String basic(String slot, String pin) {
        String value = slot + ":" + pin;
        return "Basic " + Base64.getEncoder().encodeToString(
                value.getBytes(StandardCharsets.US_ASCII));
    }

    @RestController
    static class SecurityProbeController {

        @GetMapping("/health")
        ResponseEntity<String> health() {
            return ResponseEntity.ok()
                    .cacheControl(CacheControl.noStore())
                    .body("up");
        }

        @PostMapping("/health")
        String postHealth() {
            return "must not be public";
        }

        @PostMapping("/api/v2/auth/login-options")
        String postLoginOptions() {
            return "must not be public";
        }

        @GetMapping("/api/v2/test/principal")
        PrincipalResponse principal(
                @AuthenticationPrincipal(errorOnInvalidType = true) Long participantId) {
            return new PrincipalResponse(participantId);
        }
    }

    record PrincipalResponse(long id) {}
}
