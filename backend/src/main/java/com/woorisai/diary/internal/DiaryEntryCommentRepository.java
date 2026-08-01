package com.woorisai.diary.internal;

import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

interface DiaryEntryCommentRepository extends JpaRepository<DiaryEntryComment, Long> {

    // Liveness and thread order are domain rules the caller applies to what it reads:
    // DiaryEntryComment.isActive decides visibility and IN_THREAD_ORDER orders the
    // conversation. Encoding them here makes every caller restate the contract and returns
    // wrong data, silently, when one of them forgets a clause.
    List<DiaryEntryComment> findAllByDiaryEntryId(long diaryEntryId);

    @Query("""
            select comment.diaryEntryId as diaryEntryId, count(comment) as commentCount
            from DiaryEntryComment comment
            where comment.diaryEntryId in :entryIds and comment.deletedAt is null
            group by comment.diaryEntryId
            """)
    List<DiaryEntryCommentCount> countByDiaryEntryIds(
            @Param("entryIds") Collection<Long> entryIds);
}
