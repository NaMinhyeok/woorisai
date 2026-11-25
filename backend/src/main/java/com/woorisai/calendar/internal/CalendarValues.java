package com.woorisai.calendar.internal;

import java.time.OffsetDateTime;

record CalendarValues(String title, OffsetDateTime startAt, OffsetDateTime endAt,
                      boolean allDay, String note, String kind) {
    static CalendarValues of(String title, OffsetDateTime startAt, OffsetDateTime endAt,
                             Boolean allDay, String note, String kind) {
        if (title == null || title.isBlank() || title.codePointCount(0, title.length()) > 200
                || startAt == null || endAt == null || !startAt.toInstant().isBefore(endAt.toInstant())
                || allDay == null || (note != null && note.codePointCount(0, note.length()) > 2000)
                || !("MINE".equals(kind) || "OURS".equals(kind))) {
            throw new InvalidCalendarRequestException();
        }
        String trimmed = title.strip();
        if (trimmed.isEmpty()) throw new InvalidCalendarRequestException();
        return new CalendarValues(trimmed, startAt, endAt, allDay, note, kind);
    }
}
