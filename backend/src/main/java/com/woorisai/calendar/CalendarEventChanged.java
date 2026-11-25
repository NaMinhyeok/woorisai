package com.woorisai.calendar;

/** Privacy-safe, producer-owned event. No schedule content or participant names. */
public record CalendarEventChanged(long recipientParticipantId, long calendarEventId, Action action) {
    public enum Action { CREATED, UPDATED, DELETED }

    public CalendarEventChanged {
        if (recipientParticipantId <= 0 || calendarEventId <= 0 || action == null)
            throw new IllegalArgumentException("Calendar event notification is invalid");
    }
}
