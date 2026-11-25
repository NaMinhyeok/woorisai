package com.woorisai.calendar.internal;

import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import com.woorisai.support.error.ApiErrorAdvice;
import com.woorisai.testing.PublishedSchema;
import java.time.Instant;
import java.time.OffsetDateTime;
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

class CalendarControllerTest {
    private MockMvc mvc;
    private CalendarService service;
    private static final String BODY = """
            {"title":"Together","startAt":"2026-11-25T09:00:00+09:00",
             "endAt":"2026-11-25T10:00:00+09:00","allDay":false,"note":null,"kind":"OURS"}
            """;

    @BeforeEach void setup() {
        SecurityContextHolder.getContext().setAuthentication(
                UsernamePasswordAuthenticationToken.authenticated(1L, null, List.of()));
        service = org.mockito.Mockito.mock(CalendarService.class);
        mvc = MockMvcBuilders.standaloneSetup(new CalendarController(service))
                .setControllerAdvice(ApiErrorAdvice.of(new CalendarHandlerFailures()))
                .setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver()).build();
    }
    @AfterEach void cleanup() { SecurityContextHolder.clearContext(); }

    @Test void publishesStableCreateGetListUpdateAndDeleteShapes() throws Exception {
        var start = OffsetDateTime.parse("2026-11-25T09:00:00+09:00");
        var values = CalendarValues.of("Together", start, start.plusHours(1), false, null, "OURS");
        var response = new CalendarResponse(42, "Together", start, start.plusHours(1), false,
                null, "OURS", new CalendarAuthor(1, "One"), Instant.parse("2026-11-25T00:00:00Z"),
                Instant.parse("2026-11-25T00:00:00Z"));
        given(service.create(org.mockito.ArgumentMatchers.eq(1L), org.mockito.ArgumentMatchers.any(CalendarValues.class))).willReturn(response);
        given(service.get(1, 42)).willReturn(response);
        given(service.update(org.mockito.ArgumentMatchers.eq(1L), org.mockito.ArgumentMatchers.eq(42L), org.mockito.ArgumentMatchers.any(CalendarValues.class))).willReturn(response);
        given(service.list(1, "2026-11-25", "2026-11-25")).willReturn(List.of(response));
        mvc.perform(post("/api/v2/calendar/events").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isCreated()).andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(PublishedSchema.matches("CalendarEvent"));
        mvc.perform(get("/api/v2/calendar/events/42"))
                .andExpect(status().isOk()).andExpect(PublishedSchema.matches("CalendarEvent"));
        mvc.perform(get("/api/v2/calendar/events?from=2026-11-25&to=2026-11-25"))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].author.slot").value(1));
        mvc.perform(put("/api/v2/calendar/events/42").contentType(MediaType.APPLICATION_JSON).content(BODY))
                .andExpect(status().isOk()).andExpect(PublishedSchema.matches("CalendarEvent"));
        mvc.perform(delete("/api/v2/calendar/events/42"))
                .andExpect(status().isNoContent()).andExpect(header().string("Cache-Control", "no-store"));
    }

    @Test void invalidContentUsesCalendarProblem() throws Exception {
        mvc.perform(post("/api/v2/calendar/events").contentType(MediaType.APPLICATION_JSON)
                .content(BODY.replace("\"Together\"", "\" \"")))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.errorCode").value("INVALID_CALENDAR_REQUEST"));
    }
}
