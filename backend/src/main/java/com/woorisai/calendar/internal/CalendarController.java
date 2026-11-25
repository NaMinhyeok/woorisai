package com.woorisai.calendar.internal;

import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.List;

@RestController
@RequiredArgsConstructor
class CalendarController {
    private final CalendarService service;

    @GetMapping(path = "/api/v2/calendar/events", produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<List<CalendarResponse>> list(@AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @RequestParam("from") String from, @RequestParam("to") String to) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(service.list(actor(actorId), from, to));
    }

    @PostMapping(path = "/api/v2/calendar/events", consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<CalendarResponse> create(@AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @RequestBody CalendarRequest request) {
        if (request == null) throw new InvalidCalendarRequestException();
        return ResponseEntity.status(201).cacheControl(CacheControl.noStore())
                .body(service.create(actor(actorId), request.values()));
    }

    @GetMapping(path = "/api/v2/calendar/events/{eventId}", produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<CalendarResponse> get(@AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable long eventId) {
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(service.get(actor(actorId), eventId));
    }

    @PutMapping(path = "/api/v2/calendar/events/{eventId}", consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<CalendarResponse> update(@AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable long eventId, @RequestBody CalendarRequest request) {
        if (request == null) throw new InvalidCalendarRequestException();
        return ResponseEntity.ok().cacheControl(CacheControl.noStore())
                .body(service.update(actor(actorId), eventId, request.values()));
    }

    @DeleteMapping("/api/v2/calendar/events/{eventId}")
    ResponseEntity<Void> delete(@AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable long eventId) {
        service.delete(actor(actorId), eventId);
        return ResponseEntity.noContent().cacheControl(CacheControl.noStore()).build();
    }

    private long actor(Long id) {
        if (id == null || id <= 0) throw new InvalidCalendarRequestException();
        return id;
    }
}
