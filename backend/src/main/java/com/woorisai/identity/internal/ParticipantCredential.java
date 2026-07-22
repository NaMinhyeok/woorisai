package com.woorisai.identity.internal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "participant_credential")
@Getter(AccessLevel.PACKAGE)
@NoArgsConstructor(access = AccessLevel.PROTECTED)
class ParticipantCredential {

    @Id
    @Column(name = "participant_id", nullable = false)
    private long participantId;

    @Column(name = "pin_hash", nullable = false, length = 255)
    private String pinHash;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    ParticipantCredential(long participantId, String pinHash, Instant updatedAt) {
        this.participantId = participantId;
        this.pinHash = pinHash;
        this.updatedAt = updatedAt;
    }
}
