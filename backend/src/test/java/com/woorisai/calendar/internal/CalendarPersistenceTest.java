package com.woorisai.calendar.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.calendar.CalendarEventChanged;
import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantReference;
import java.time.OffsetDateTime;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.persistence.autoconfigure.EntityScan;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Bean;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.event.ApplicationEvents;
import org.springframework.test.context.event.RecordApplicationEvents;
import org.springframework.test.context.TestPropertySource;

@SpringBootTest(classes = CalendarPersistenceTest.TestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@TestPropertySource(locations = "classpath:clean-schema-h2.properties", properties = {
        "spring.autoconfigure.exclude=org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration,"
            + "org.springframework.modulith.events.jpa.JpaEventPublicationAutoConfiguration,"
            + "org.springframework.modulith.events.config.EventPublicationAutoConfiguration",
        "spring.datasource.url=jdbc:h2:mem:calendar-clean-schema;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE"
})
@RecordApplicationEvents
class CalendarPersistenceTest {
    @Autowired ApplicationEvents applicationEvents;
    @Autowired CalendarService service;
    @Autowired JdbcTemplate jdbc;
    private static final OffsetDateTime START = OffsetDateTime.parse("2026-11-25T09:00:00+09:00");

    @BeforeEach void reset() {
        jdbc.update("DELETE FROM woorisai.calendar_event");
        jdbc.update("DELETE FROM woorisai.participant");
        jdbc.update("INSERT INTO woorisai.participant(id,slot,display_name,created_at) VALUES (1,1,'One',CURRENT_TIMESTAMP)");
        jdbc.update("INSERT INTO woorisai.participant(id,slot,display_name,created_at) VALUES (2,2,'Two',CURRENT_TIMESTAMP)");
    }

    @Test void overlapsInclusiveDayRangeAndBothParticipantsRead() {
        var early = service.create(1, values("early", START.minusDays(1), START.plusMinutes(1), "MINE"));
        var late = service.create(2, values("late", START.plusDays(1), START.plusDays(2), "OURS"));
        assertThat(service.list(2, "2026-11-25", "2026-11-25"))
                .extracting(CalendarResponse::id).containsExactly(early.id());
        assertThat(service.get(1, late.id()).author().slot()).isEqualTo(2);
        assertThatThrownBy(() -> service.list(1, "2026-11-26", "2026-11-25"))
                .isInstanceOf(InvalidCalendarRequestException.class);
        assertThatThrownBy(() -> service.list(1, "+999999999-12-31", "+999999999-12-31"))
                .isInstanceOf(InvalidCalendarRequestException.class);
        assertThatThrownBy(() -> service.list(1, "2026-01-01", "2027-02-01"))
                .isInstanceOf(InvalidCalendarRequestException.class);
    }

    @Test void sharedEventCanBeEditedAndDeletedByPartnerButMineCannot() {
        var mine = service.create(1, values("mine", START, START.plusHours(1), "MINE"));
        assertThatThrownBy(() -> service.update(2, mine.id(), values("wrong", START, START.plusHours(1), "OURS")))
                .isInstanceOf(CalendarForbiddenException.class);
        var ours = service.create(1, values("ours", START, START.plusHours(1), "OURS"));
        var updated = service.update(2, ours.id(), values("updated", START, START.plusHours(2), "MINE"));
        assertThat(updated.author().slot()).isEqualTo(1);
        assertThat(applicationEvents.stream(CalendarEventChanged.class).toList()).containsExactly(
                new CalendarEventChanged(2, mine.id(), CalendarEventChanged.Action.CREATED),
                new CalendarEventChanged(2, ours.id(), CalendarEventChanged.Action.CREATED),
                new CalendarEventChanged(1, ours.id(), CalendarEventChanged.Action.UPDATED));
        assertThatThrownBy(() -> service.delete(2, ours.id())).isInstanceOf(CalendarForbiddenException.class);
        service.delete(1, ours.id());
        assertThat(applicationEvents.stream(CalendarEventChanged.class).toList()).contains(
                new CalendarEventChanged(2, ours.id(), CalendarEventChanged.Action.DELETED));
        assertThatThrownBy(() -> service.get(2, ours.id())).isInstanceOf(CalendarNotFoundException.class);
    }

    private static CalendarValues values(String title, OffsetDateTime start, OffsetDateTime end, String kind) {
        return CalendarValues.of(title, start, end, false, null, kind);
    }

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackageClasses = CalendarEvent.class)
    @EnableJpaRepositories(basePackageClasses = CalendarEventRepository.class)
    static class TestApplication {
        @Bean ParticipantDirectory participants() {
            return () -> new CanonicalParticipantPair(
                    new ParticipantReference(1, 1, "One"), new ParticipantReference(2, 2, "Two"));
        }
        @Bean CalendarService calendar(CalendarEventRepository repository, ParticipantDirectory participants,
                                       org.springframework.context.ApplicationEventPublisher events, java.time.Clock clock) {
            return new CalendarService(repository, participants, events, clock);
        }
        @Bean java.time.Clock clock() { return java.time.Clock.systemUTC(); }
    }
}
