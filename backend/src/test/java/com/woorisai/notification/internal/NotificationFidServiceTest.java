package com.woorisai.notification.internal;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.woorisai.notification.internal.NotificationFidService.NotificationFidUnavailableException;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class NotificationFidServiceTest {

    private static final long PARTICIPANT_ID = 3_000_000_001L;
    private static final String FID = "c123456789012345678901";
    private static final FirebaseInstallationId INSTALLATION_ID =
            FirebaseInstallationId.parse(FID);
    private static final Instant CLOCK_TIME =
            Instant.parse("2026-07-21T03:04:05.123456789Z");
    private static final Instant STORED_TIME =
            Instant.parse("2026-07-21T03:04:05.123456Z");

    private NotificationFidRepository fids;
    private NotificationFidService service;

    @BeforeEach
    void setUp() {
        fids = mock(NotificationFidRepository.class);
        service = new NotificationFidService(
                fids,
                Clock.fixed(CLOCK_TIME, ZoneOffset.UTC));
    }

    @Test
    void registersTheValueObjectAtTheInjectedServerTime() {
        when(fids.upsert(PARTICIPANT_ID, FID, STORED_TIME)).thenReturn(1);

        service.register(PARTICIPANT_ID, INSTALLATION_ID);

        verify(fids).upsert(PARTICIPANT_ID, FID, STORED_TIME);
    }

    @Test
    void unregistersOnlyTheRequestedParticipantsValueObject() {
        service.unregister(PARTICIPANT_ID, INSTALLATION_ID);

        verify(fids).deleteByFidAndParticipantId(FID, PARTICIPANT_ID);
    }

    @Test
    void reportsAnUnavailableAtomicUpsert() {
        when(fids.upsert(PARTICIPANT_ID, FID, STORED_TIME)).thenReturn(0);

        assertThatThrownBy(() -> service.register(PARTICIPANT_ID, INSTALLATION_ID))
                .isInstanceOf(NotificationFidUnavailableException.class);
    }
}
