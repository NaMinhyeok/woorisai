package com.woorisai.notification.internal;

import java.time.Instant;
import java.util.List;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

interface NotificationFidRepository extends Repository<NotificationFid, Long> {

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            INSERT INTO woorisai.notification_fid (participant_id, fid, created_at)
            VALUES (:participantId, :fid, :createdAt)
            ON CONFLICT (fid) DO UPDATE
            SET participant_id = EXCLUDED.participant_id,
                created_at = EXCLUDED.created_at
            """, nativeQuery = true)
    int upsert(
            @Param("participantId") long participantId,
            @Param("fid") String fid,
            @Param("createdAt") Instant createdAt);

    List<NotificationFid> findAllByParticipantIdOrderByIdAsc(long participantId);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from NotificationFid target where target.fid = :fid")
    int deleteByFid(@Param("fid") String fid);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            delete from NotificationFid target
            where target.fid = :fid and target.participantId = :participantId
            """)
    int deleteByFidAndParticipantId(
            @Param("fid") String fid,
            @Param("participantId") long participantId);
}
