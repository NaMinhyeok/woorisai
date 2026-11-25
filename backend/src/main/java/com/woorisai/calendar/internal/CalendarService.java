package com.woorisai.calendar.internal;

import com.woorisai.calendar.CalendarEventChanged;
import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantReference;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
class CalendarService {
    private final CalendarEventRepository repository;
    private final ParticipantDirectory participants;
    private final ApplicationEventPublisher events;
    private final Clock clock;

    @Transactional(readOnly = true)
    List<CalendarResponse> list(long actorId, String from, String to) {
        CanonicalParticipantPair pair = pair(actorId);
        LocalDate first, last;
        try {
            first = LocalDate.parse(from);
            last = LocalDate.parse(to);
            if (!first.toString().equals(from) || !last.toString().equals(to)
                    || last.isBefore(first) || ChronoUnit.DAYS.between(first, last) > 366
                    || last.equals(LocalDate.MAX))
                throw new InvalidCalendarRequestException();
        } catch (RuntimeException exception) {
            if (exception instanceof InvalidCalendarRequestException) throw exception;
            throw new InvalidCalendarRequestException();
        }
        return repository.findOverlapping(first.atStartOfDay().atOffset(ZoneOffset.UTC),
                        last.plusDays(1).atStartOfDay().atOffset(ZoneOffset.UTC)).stream()
                .map(event -> response(event, pair)).toList();
    }

    @Transactional(readOnly = true)
    CalendarResponse get(long actorId, long id) {
        return response(live(id), pair(actorId));
    }

    @Transactional
    CalendarResponse create(long actorId, CalendarValues values) {
        CanonicalParticipantPair pair = pair(actorId);
        CalendarEvent event = repository.saveAndFlush(CalendarEvent.create(actorId, values, now()));
        publish(pair, actorId, event.getId(), CalendarEventChanged.Action.CREATED);
        return response(event, pair);
    }

    @Transactional
    CalendarResponse update(long actorId, long id, CalendarValues values) {
        CanonicalParticipantPair pair = pair(actorId);
        CalendarEvent event = live(id);
        event.reviseBy(actorId, values, now());
        flush();
        publish(pair, actorId, id, CalendarEventChanged.Action.UPDATED);
        return response(event, pair);
    }

    @Transactional
    void delete(long actorId, long id) {
        CanonicalParticipantPair pair = pair(actorId);
        CalendarEvent event = live(id);
        event.deleteBy(actorId, now());
        flush();
        publish(pair, actorId, id, CalendarEventChanged.Action.DELETED);
    }

    private CalendarEvent live(long id) {
        if (id <= 0) throw new InvalidCalendarRequestException();
        return repository.findById(id).filter(CalendarEvent::isActive)
                .orElseThrow(CalendarNotFoundException::new);
    }
    private CanonicalParticipantPair pair(long actorId) {
        if (actorId <= 0) throw new CalendarForbiddenException();
        CanonicalParticipantPair pair;
        try { pair = participants.canonicalPair(); }
        catch (ParticipantDirectory.ParticipantPairUnavailableException exception) {
            throw new CalendarUnavailableException();
        }
        if (pair.findById(actorId).isEmpty()) throw new CalendarForbiddenException();
        return pair;
    }
    private CalendarResponse response(CalendarEvent event, CanonicalParticipantPair pair) {
        ParticipantReference author = pair.findById(event.getAuthorId())
                .orElseThrow(CalendarUnavailableException::new);
        return CalendarResponse.of(event, author);
    }
    private void publish(CanonicalParticipantPair pair, long actorId, long id, CalendarEventChanged.Action action) {
        long recipient = pair.partnerOf(actorId).orElseThrow(CalendarUnavailableException::new).id();
        events.publishEvent(new CalendarEventChanged(recipient, id, action));
    }
    private void flush() {
        try { repository.flush(); }
        catch (OptimisticLockingFailureException exception) { throw new CalendarConflictException(exception); }
    }
    private Instant now() { return Instant.now(clock).truncatedTo(ChronoUnit.MICROS); }
}
