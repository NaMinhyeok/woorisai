package com.woorisai.calendar.internal;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import com.woorisai.support.error.ApiErrorAdvice;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.method.annotation.AuthenticationPrincipalArgumentResolver;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class CalendarRequestHttpTest {
    private MockMvc mvc;
    private static final String VALID = """
            {"title":"Dinner","startAt":"2026-11-25T09:00:00+09:00",
            "endAt":"2026-11-25T10:00:00+09:00","allDay":false,"note":null,"kind":"OURS"}
            """;
    @BeforeEach void setup() {
        SecurityContextHolder.getContext().setAuthentication(
                UsernamePasswordAuthenticationToken.authenticated(1L, null, List.of()));
        mvc = MockMvcBuilders.standaloneSetup(new CalendarController(org.mockito.Mockito.mock(CalendarService.class)))
                .setControllerAdvice(ApiErrorAdvice.of(new CalendarHandlerFailures()))
                .setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver()).build();
    }
    @AfterEach void cleanup() { SecurityContextHolder.clearContext(); }
    @Test void omittedNullableNoteIsNotAFullReplacement() throws Exception {
        mvc.perform(post("/api/v2/calendar/events").contentType(MediaType.APPLICATION_JSON)
                        .content(VALID.replace("\"note\":null,", "")))
                .andExpect(status().isBadRequest());
    }
    @Test void offsetIsRequired() throws Exception {
        mvc.perform(post("/api/v2/calendar/events").contentType(MediaType.APPLICATION_JSON)
                        .content(VALID.replace("09:00:00+09:00", "09:00:00")))
                .andExpect(status().isBadRequest());
    }
}
