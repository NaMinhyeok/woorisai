package com.woorisai.notification.internal;

import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.woorisai.notification.internal.NotificationFidService.NotificationFidUnavailableException;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.converter.json.JacksonJsonHttpMessageConverter;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.method.annotation.AuthenticationPrincipalArgumentResolver;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import tools.jackson.databind.DeserializationFeature;
import tools.jackson.databind.MapperFeature;
import tools.jackson.databind.json.JsonMapper;

class NotificationFidControllerTest {

    private static final long ACTOR_ID = 3_000_000_001L;
    private static final String FID = "c123456789012345678901";
    private static final FirebaseInstallationId INSTALLATION_ID =
            FirebaseInstallationId.parse(FID);

    private NotificationFidService notificationFids;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        SecurityContextHolder.getContext().setAuthentication(
                UsernamePasswordAuthenticationToken.authenticated(ACTOR_ID, null, List.of()));
        notificationFids = mock(NotificationFidService.class);
        mvc = MockMvcBuilders.standaloneSetup(
                        new NotificationFidController(notificationFids))
                .setControllerAdvice(new NotificationFidApiExceptionHandler())
                .setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver())
                .setMessageConverters(new JacksonJsonHttpMessageConverter(
                        JsonMapper.builder()
                                .enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
                                .disable(DeserializationFeature.ACCEPT_FLOAT_AS_INT)
                                .disable(MapperFeature.ALLOW_COERCION_OF_SCALARS)))
                .build();
    }

    @AfterEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void registersAndUnregistersTheAuthenticatedParticipantsFid() throws Exception {
        String body = "{\"fid\":\"" + FID + "\"}";

        mvc.perform(post("/api/v2/notification-fids")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isNoContent())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"));

        mvc.perform(delete("/api/v2/notification-fids")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isNoContent())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"));

        verify(notificationFids).register(ACTOR_ID, INSTALLATION_ID);
        verify(notificationFids).unregister(ACTOR_ID, INSTALLATION_ID);
    }

    @Test
    void mapsInvalidFidValuesToAStableNoStoreProblem() throws Exception {
        for (String body : new String[] {
                "{\"fid\":\"too-short\"}",
                "{\"fid\":\"c12345678901234567890!\"}",
                "{\"fid\":null}",
                "null"
        }) {
            assertInvalidProblem(body);
        }

        verifyNoInteractions(notificationFids);
    }

    @Test
    void mapsWrongJsonTypesAndMalformedJsonToTheSameStableProblem() throws Exception {
        assertInvalidProblem("{\"fid\":123}");
        assertInvalidProblem("{\"fid\":");

        verifyNoInteractions(notificationFids);
    }

    @Test
    void normalizesServiceAndDataAvailabilityFailures() throws Exception {
        doThrow(new NotificationFidUnavailableException())
                .when(notificationFids).register(ACTOR_ID, INSTALLATION_ID);

        mvc.perform(post("/api/v2/notification-fids")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fid\":\"" + FID + "\"}"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(content().contentTypeCompatibleWith(
                        MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("NOTIFICATION_FID_UNAVAILABLE"));

        doThrow(new DataAccessResourceFailureException("redacted"))
                .when(notificationFids).unregister(ACTOR_ID, INSTALLATION_ID);

        mvc.perform(delete("/api/v2/notification-fids")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"fid\":\"" + FID + "\"}"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("NOTIFICATION_FID_UNAVAILABLE"));
    }

    private void assertInvalidProblem(String body) throws Exception {
        mvc.perform(post("/api/v2/notification-fids")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(
                        MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.title").value("Invalid notification FID request"))
                .andExpect(jsonPath("$.errorCode").value("INVALID_NOTIFICATION_FID"));
    }
}
