package com.woorisai.diary.internal;

import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

interface DiaryEntryCommentRepository extends JpaRepository<DiaryEntryComment, Long> {

    List<DiaryEntryComment> findAllByDiaryEntryIdOrderByCreatedAtAscIdAsc(long diaryEntryId);

    @Query("""
            select comment.diaryEntryId as diaryEntryId, count(comment) as commentCount
            from DiaryEntryComment comment
            where comment.diaryEntryId in :entryIds
            group by comment.diaryEntryId
            """)
    List<DiaryEntryCommentCount> countByDiaryEntryIds(
            @Param("entryIds") Collection<Long> entryIds);
}
