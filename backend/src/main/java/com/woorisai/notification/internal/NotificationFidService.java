package com.woorisai.notification.internal;

import java.time.Clock;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Objects;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
class NotificationFidService {

    private final NotificationFidRepository fids;
    private final Clock clock;

    NotificationFidService(
            NotificationFidRepository fids,
            Clock clock) {
        this.fids = Objects.requireNonNull(fids, "fids");
        this.clock = Objects.requireNonNull(clock, "clock");
    }

    @Transactional
    void register(long participantId, FirebaseInstallationId fid) {
        int affected = fids.upsert(
                participantId,
                fid.value(),
                Instant.now(clock).truncatedTo(ChronoUnit.MICROS));
        if (affected != 1) {
            throw new NotificationFidUnavailableException();
        }
    }

    @Transactional
    void unregister(long participantId, FirebaseInstallationId fid) {
        fids.deleteByFidAndParticipantId(fid.value(), participantId);
    }

    static final class NotificationFidUnavailableException extends RuntimeException {

        NotificationFidUnavailableException() {
            super("Notification FID service is unavailable");
        }
    }
}
