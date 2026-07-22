package com.woorisai.relationship.internal;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

interface RelationshipScoreRepository extends JpaRepository<RelationshipScore, Long> {

    List<RelationshipScore> findAllByOrderBySourceParticipantIdAsc();
}
