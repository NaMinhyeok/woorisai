package com.woorisai.participant.internal;

import java.util.List;
import org.springframework.data.repository.Repository;

interface ParticipantRepository extends Repository<Participant, Long> {

    List<Participant> findAllByOrderBySlotAsc();
}
