package com.woorisai.diary.internal;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

interface DiaryEntryCommentRepository extends JpaRepository<DiaryEntryComment, Long> {

    List<DiaryEntryComment> findAllByDiaryEntryIdAndDeletedAtIsNullOrderByCreatedAtAscIdAsc(
            long diaryEntryId);

    List<DiaryEntryComment> findAllByDiaryEntryIdAndDeletedAtIsNull(long diaryEntryId);

    Optional<DiaryEntryComment> findByIdAndDeletedAtIsNull(long id);

    @Query("""
            select comment.diaryEntryId as diaryEntryId, count(comment) as commentCount
            from DiaryEntryComment comment
            where comment.diaryEntryId in :entryIds and comment.deletedAt is null
            group by comment.diaryEntryId
            """)
    List<DiaryEntryCommentCount> countByDiaryEntryIds(
            @Param("entryIds") Collection<Long> entryIds);
}
