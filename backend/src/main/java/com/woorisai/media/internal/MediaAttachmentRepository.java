package com.woorisai.media.internal;

import jakarta.persistence.LockModeType;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

interface MediaAttachmentRepository extends JpaRepository<MediaAttachment, UUID> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select media from MediaAttachment media where media.id = :id")
    Optional<MediaAttachment> findByIdForUpdate(@Param("id") UUID id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
            select media
            from MediaAttachment media
            where media.id in :ids
            order by media.id
            """)
    List<MediaAttachment> findAllByIdForUpdate(@Param("ids") Collection<UUID> ids);

    @Query("""
            select media.id
            from MediaAttachment media
            where media.diaryEntryId = :diaryEntryId
            order by media.id
            """)
    List<UUID> findIdsByDiaryEntryId(@Param("diaryEntryId") long diaryEntryId);

    List<MediaAttachment> findAllByPurposeAndStatusAndScoreChangeIdInOrderByScoreChangeIdAscPositionAscIdAsc(
            MediaPurpose purpose,
            MediaStatus status,
            Collection<Long> parentIds);

    List<MediaAttachment> findAllByPurposeAndStatusAndScoreChangeCommentIdInOrderByScoreChangeCommentIdAscPositionAscIdAsc(
            MediaPurpose purpose,
            MediaStatus status,
            Collection<Long> parentIds);

    List<MediaAttachment> findAllByPurposeAndStatusAndDiaryEntryIdInOrderByDiaryEntryIdAscPositionAscIdAsc(
            MediaPurpose purpose,
            MediaStatus status,
            Collection<Long> parentIds);
}
