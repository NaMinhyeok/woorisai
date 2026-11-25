package com.woorisai.calendar.internal;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.woorisai.participant.ParticipantReference;
import java.time.Instant;
import java.time.OffsetDateTime;

record CalendarRequest(String title, OffsetDateTime startAt, OffsetDateTime endAt,
                       Boolean allDay, @JsonProperty(required = true) String note, String kind) {
    CalendarValues values() { return CalendarValues.of(title, startAt, endAt, allDay, note, kind); }
}
record CalendarAuthor(int slot, String displayName) {
    static CalendarAuthor from(ParticipantReference author) {
        return new CalendarAuthor(author.slot(), author.displayName());
    }
}
record CalendarResponse(long id, String title, OffsetDateTime startAt, OffsetDateTime endAt,
                        boolean allDay, String note, String kind, CalendarAuthor author,
                        Instant createdAt, Instant updatedAt) {
    static CalendarResponse of(CalendarEvent event, ParticipantReference author) {
        return new CalendarResponse(event.getId(), event.getTitle(), event.getStartAt(), event.getEndAt(),
                event.isAllDay(), event.getNote(), event.getKind(), CalendarAuthor.from(author),
                event.getCreatedAt(), event.getUpdatedAt());
    }
}
