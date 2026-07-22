package com.woorisai.participant.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantDirectory.ParticipantPairUnavailableException;
import com.woorisai.participant.ParticipantReference;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.persistence.autoconfigure.EntityScan;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;

@SpringBootTest(
        classes = ParticipantDirectoryCleanSchemaTest.TestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@TestPropertySource(
        locations = "classpath:clean-schema-h2.properties",
        properties = {
            "spring.autoconfigure.exclude="
                + "org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration,"
                + "org.springframework.modulith.events.jpa.JpaEventPublicationAutoConfiguration,"
                + "org.springframework.modulith.events.config.EventPublicationAutoConfiguration",
            "spring.datasource.url=jdbc:h2:mem:participant-clean-schema;"
                + "MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;"
                + "DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE"
})
class ParticipantDirectoryCleanSchemaTest {

    private static final long FIRST_ID = 3_000_000_001L;
    private static final long SECOND_ID = 3_000_000_002L;

    @Autowired
    private ParticipantDirectory participants;

    @Autowired
    private JdbcTemplate jdbc;

    @Test
    void validatesTheCleanMappingAndFailsClosedUntilTheOrderedPairExists() {
        assertThatThrownBy(participants::canonicalPair)
                .isInstanceOf(ParticipantPairUnavailableException.class);

        insertParticipant(SECOND_ID, 2, "Fixture Two", "2026-07-21T00:00:02Z");

        assertThatThrownBy(participants::canonicalPair)
                .isInstanceOf(ParticipantPairUnavailableException.class);

        insertParticipant(FIRST_ID, 1, "Fixture One", "2026-07-21T00:00:01Z");

        assertThat(participants.canonicalPair().inSlotOrder()).containsExactly(
                new ParticipantReference(FIRST_ID, 1, "Fixture One"),
                new ParticipantReference(SECOND_ID, 2, "Fixture Two"));
        assertThat(participants.canonicalPair().inSlotOrder())
                .extracting(ParticipantReference::id)
                .allSatisfy(id -> assertThat(id).isGreaterThan((long) Integer.MAX_VALUE));
    }

    private void insertParticipant(
            long id,
            int slot,
            String displayName,
            String createdAt) {
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, ?, ?, CAST(? AS TIMESTAMP WITH TIME ZONE))
                """, id, slot, displayName, createdAt);
    }

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackages = "com.woorisai.participant.internal")
    @EnableJpaRepositories(basePackages = "com.woorisai.participant.internal")
    @ComponentScan(basePackages = "com.woorisai.participant.internal")
    static class TestApplication {
    }
}
