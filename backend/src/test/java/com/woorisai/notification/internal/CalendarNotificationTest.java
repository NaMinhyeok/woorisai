package com.woorisai.notification.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.woorisai.calendar.CalendarEventChanged;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class CalendarNotificationTest {
    @Test void sendsOnlyEventTypeAndIdToThePartner() {
        NotificationFidRepository fids = mock(NotificationFidRepository.class);
        String fid = "c123456789012345678901";
        when(fids.findAllByParticipantIdOrderByIdAsc(2)).thenReturn(List.of(new NotificationFid(2, fid, java.time.Instant.now())));
        List<NotificationSender.NotificationMessage> sent = new ArrayList<>();
        NotificationEventListener listener = new NotificationEventListener(fids, sent::add);
        listener.calendarEventChanged(new CalendarEventChanged(2, 7, CalendarEventChanged.Action.CREATED));
        listener.calendarEventChanged(new CalendarEventChanged(2, 7, CalendarEventChanged.Action.UPDATED));
        listener.calendarEventChanged(new CalendarEventChanged(2, 7, CalendarEventChanged.Action.DELETED));
        assertThat(sent).extracting(message -> message.eventType().wireName())
                .containsExactly("calendarEventCreated", "calendarEventUpdated", "calendarEventDeleted");
        assertThat(sent).extracting(NotificationSender.NotificationMessage::resourceId)
                .containsExactly(7L, 7L, 7L);
    }
}
