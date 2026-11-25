package com.woorisai.calendar.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.OffsetDateTime;
import org.junit.jupiter.api.Test;

class CalendarPolicyTest {
    private static final OffsetDateTime START = OffsetDateTime.parse("2026-11-25T09:00:00+09:00");

    @Test
    void rejectsInvalidIntervalsAndOversizedContent() {
        assertThatThrownBy(() -> CalendarValues.of("Meeting", START, START, false, null, "OURS"))
                .isInstanceOf(InvalidCalendarRequestException.class);
        assertThatThrownBy(() -> CalendarValues.of(" ", START, START.plusHours(1), false, null, "MINE"))
                .isInstanceOf(InvalidCalendarRequestException.class);
        assertThatThrownBy(() -> CalendarValues.of("x".repeat(201), START, START.plusHours(1), false, null, "OURS"))
                .isInstanceOf(InvalidCalendarRequestException.class);
        assertThatThrownBy(() -> CalendarValues.of("ok", START, START.plusHours(1), false, "x".repeat(2001), "OURS"))
                .isInstanceOf(InvalidCalendarRequestException.class);
    }

    @Test
    void mineIsAuthorOwnedButOursIsMutual() {
        var mine = CalendarValues.of("Mine", START, START.plusHours(1), false, null, "MINE");
        var ours = CalendarValues.of("Ours", START, START.plusHours(1), false, null, "OURS");
        assertThatThrownBy(() -> CalendarEvent.create(1, mine, START.toInstant()).reviseBy(2, mine, START.toInstant()))
                .isInstanceOf(CalendarForbiddenException.class);
        var event = CalendarEvent.create(1, ours, START.toInstant());
        event.reviseBy(2, mine, START.plusHours(2).toInstant());
        assertThat(event.getAuthorId()).isEqualTo(1);
        assertThat(event.getKind()).isEqualTo("MINE");
        assertThatThrownBy(() -> event.deleteBy(2))
                .isInstanceOf(CalendarForbiddenException.class);
    }
}
