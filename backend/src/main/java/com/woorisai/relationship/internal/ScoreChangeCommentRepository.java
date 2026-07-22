package com.woorisai.relationship.internal;

import java.util.Collection;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

interface ScoreChangeCommentRepository extends JpaRepository<ScoreChangeComment, Long> {

    List<ScoreChangeComment> findByScoreChangeIdOrderByCreatedAtAscIdAsc(long scoreChangeId);

    @Query("""
            select comment.scoreChangeId as scoreChangeId, count(comment.id) as commentCount
            from ScoreChangeComment comment
            where comment.scoreChangeId in :scoreChangeIds
            group by comment.scoreChangeId
            """)
    List<CommentCount> countByScoreChangeIds(@Param("scoreChangeIds") Collection<Long> scoreChangeIds);

    interface CommentCount {

        long getScoreChangeId();

        long getCommentCount();
    }
}
