package com.woorisai.notification.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "notification_fid")
@Getter(AccessLevel.PACKAGE)
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class NotificationFid {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id", nullable = false)
    private Long id;

    @Column(name = "participant_id", nullable = false)
    private long participantId;

    @Column(name = "fid", nullable = false, unique = true, length = 255)
    private String fid;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    NotificationFid(long participantId, String fid, Instant createdAt) {
        this.participantId = participantId;
        this.fid = fid;
        this.createdAt = createdAt;
    }

    FirebaseInstallationId installationId() {
        return FirebaseInstallationId.parse(fid);
    }
}
