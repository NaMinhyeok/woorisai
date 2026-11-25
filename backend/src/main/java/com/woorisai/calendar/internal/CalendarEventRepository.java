package com.woorisai.calendar.internal;

import java.time.OffsetDateTime;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

interface CalendarEventRepository extends JpaRepository<CalendarEvent, Long> {
    @Query("select e from CalendarEvent e where e.deletedAt is null and e.startAt < :end and e.endAt > :start order by e.startAt asc, e.id asc")
    List<CalendarEvent> findOverlapping(@Param("start") OffsetDateTime start, @Param("end") OffsetDateTime end);
}
