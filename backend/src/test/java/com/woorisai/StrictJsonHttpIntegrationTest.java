package com.woorisai;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.woorisai.relationship.RelationshipScoreChanged;
import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;
import java.util.Base64;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.CannotCreateTransactionException;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

@SpringBootTest
@AutoConfigureMockMvc
@Import(StrictJsonHttpIntegrationTest.RollbackConfiguration.class)
@TestPropertySource(
        locations = "classpath:clean-schema-h2.properties",
        properties = {
            "spring.datasource.url=jdbc:h2:mem:strict-json-http;"
                + "MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;"
                + "DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE",
})
class StrictJsonHttpIntegrationTest {

    private static final long FIRST = 3_000_000_001L;
    private static final long SECOND = 3_000_000_002L;
    private static final OffsetDateTime NOW =
            OffsetDateTime.parse("2026-07-21T00:00:00Z");

    @Autowired
    private MockMvc mvc;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private ProducerRollbackProbe rollbackProbe;

    @BeforeEach
    void canonicalPairAndCredentials() {
        rollbackProbe.disarm();
        jdbc.update("DELETE FROM woorisai.event_publication");
        jdbc.update("DELETE FROM woorisai.notification_fid");
        jdbc.update("DELETE FROM woorisai.media_attachment");
        jdbc.update("DELETE FROM woorisai.score_change_comment");
        jdbc.update("DELETE FROM woorisai.score_change");
        jdbc.update("DELETE FROM woorisai.relationship_score");
        jdbc.update("DELETE FROM woorisai.participant_credential");
        jdbc.update("DELETE FROM woorisai.participant");
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, 1, 'Fixture One', ?), (?, 2, 'Fixture Two', ?)
                """, FIRST, NOW, SECOND, NOW);
        jdbc.update("""
                INSERT INTO woorisai.participant_credential (
                    participant_id, pin_hash, updated_at
                ) VALUES (?, ?, ?)
                """, FIRST, passwordEncoder.encode("0123"), NOW);
        jdbc.update("""
                INSERT INTO woorisai.relationship_score (
                    id, source_participant_id, target_participant_id,
                    current_score, updated_at
                ) VALUES (10, ?, ?, 50, ?), (11, ?, ?, 70, ?)
                """, FIRST, SECOND, NOW, SECOND, FIRST, NOW);
    }

    @Test
    void rejectsScalarCoercionThroughTheProductionHttpMapper() throws Exception {
        List<String> invalidBodies = List.of(
                "{\"delta\":\"1\",\"mediaUploadIds\":[]}",
                "{\"delta\":1.5,\"mediaUploadIds\":[]}",
                "{\"delta\":true,\"mediaUploadIds\":[]}",
                "{\"delta\":1,\"reason\":123,\"mediaUploadIds\":[]}");

        for (String body : invalidBodies) {
            mvc.perform(post("/api/v2/score-changes")
                            .header(HttpHeaders.AUTHORIZATION, basic("1", "0123"))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest())
                    .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                    .andExpect(jsonPath("$.errorCode")
                            .value("INVALID_RELATIONSHIP_REQUEST"));
        }

        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.score_change",
                Integer.class)).isZero();
    }

    @Test
    void rollsBackTheBusinessWriteAndPublicationTogetherWhenTheProducerRollsBack()
            throws Exception {
        rollbackProbe.arm();

        mvc.perform(post("/api/v2/score-changes")
                        .header(HttpHeaders.AUTHORIZATION, basic("1", "0123"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"delta\":1,\"mediaUploadIds\":[]}"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("RELATIONSHIP_UNAVAILABLE"));

        assertThat(jdbc.queryForObject("""
                SELECT current_score
                FROM woorisai.relationship_score
                WHERE source_participant_id = ?
                """, Integer.class, FIRST)).isEqualTo(50);
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.score_change",
                Integer.class)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.event_publication",
                Integer.class)).isZero();
    }

    private static String basic(String slot, String pin) {
        return "Basic " + Base64.getEncoder().encodeToString(
                (slot + ":" + pin).getBytes(StandardCharsets.US_ASCII));
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class RollbackConfiguration {

        @Bean
        ProducerRollbackProbe producerRollbackProbe() {
            return new ProducerRollbackProbe();
        }
    }

    static final class ProducerRollbackProbe {

        private final AtomicBoolean armed = new AtomicBoolean();

        void arm() {
            armed.set(true);
        }

        void disarm() {
            armed.set(false);
        }

        @TransactionalEventListener(phase = TransactionPhase.BEFORE_COMMIT)
        void rollBackProducer(RelationshipScoreChanged event) {
            if (armed.getAndSet(false)) {
                throw new CannotCreateTransactionException("Synthetic producer rollback");
            }
        }
    }
}
