package com.woorisai.calendar.internal;

import jakarta.persistence.*;
import java.time.Instant;
import java.time.OffsetDateTime;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "calendar_event")
@Getter(AccessLevel.PACKAGE)
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class CalendarEvent {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "author_id", nullable = false)
    private long authorId;
    @Column(nullable = false, length = 200)
    private String title;
    @Column(name = "start_at", nullable = false)
    private OffsetDateTime startAt;
    @Column(name = "end_at", nullable = false)
    private OffsetDateTime endAt;
    @Column(name = "all_day", nullable = false)
    private boolean allDay;
    @Column(length = 2000)
    private String note;
    @Column(nullable = false, length = 4)
    private String kind;
    @Column(name = "created_at", nullable = false)
    private Instant createdAt;
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;
    @Version @Column(nullable = false)
    private long version;
    @Column(name = "deleted_at")
    private Instant deletedAt;

    static CalendarEvent create(long authorId, CalendarValues values, Instant now) {
        if (authorId <= 0) throw new InvalidCalendarRequestException();
        CalendarEvent event = new CalendarEvent();
        event.authorId = authorId;
        event.apply(values);
        event.createdAt = now;
        event.updatedAt = now;
        return event;
    }

    boolean isActive() { return deletedAt == null; }

    void reviseBy(long actorId, CalendarValues values, Instant now) {
        requireMutationBy(actorId);
        apply(values);
        updatedAt = now.isBefore(createdAt) ? createdAt : now;
    }

    void deleteBy(long actorId) { requireMutationBy(actorId); }
    void deleteBy(long actorId, Instant now) {
        requireMutationBy(actorId);
        deletedAt = now.isBefore(createdAt) ? createdAt : now;
    }

    private void requireMutationBy(long actorId) {
        if (actorId <= 0 || ("MINE".equals(kind) && actorId != authorId))
            throw new CalendarForbiddenException();
    }

    private void apply(CalendarValues values) {
        title = values.title(); startAt = values.startAt(); endAt = values.endAt();
        allDay = values.allDay(); note = values.note(); kind = values.kind();
    }
}
