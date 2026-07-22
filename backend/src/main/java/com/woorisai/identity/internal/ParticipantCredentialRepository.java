package com.woorisai.identity.internal;

import java.util.Optional;
import org.springframework.data.repository.Repository;

interface ParticipantCredentialRepository extends Repository<ParticipantCredential, Long> {

    Optional<ParticipantCredential> findById(Long participantId);
}
