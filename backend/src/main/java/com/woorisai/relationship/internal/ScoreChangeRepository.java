package com.woorisai.relationship.internal;

import java.util.Collection;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

interface ScoreChangeRepository extends JpaRepository<ScoreChange, Long> {

    Page<ScoreChange> findByRelationshipScoreIdInOrderByCreatedAtDescIdDesc(
            Collection<Long> relationshipScoreIds,
            Pageable pageable);
}
