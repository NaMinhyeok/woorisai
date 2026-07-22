package com.woorisai.relationship.internal;

import static org.assertj.core.api.Assertions.assertThat;

import com.woorisai.media.AttachScoreChangeMediaCommand;
import com.woorisai.media.AttachScoreCommentMediaCommand;
import com.woorisai.media.AttachedMedia;
import com.woorisai.media.AttachedMediaQuery;
import com.woorisai.media.DiaryEntryMediaParent;
import com.woorisai.media.MediaAttachmentMutation;
import com.woorisai.media.ReplaceDiaryEntryMediaCommand;
import com.woorisai.media.ScoreChangeMediaParent;
import com.woorisai.media.ScoreCommentMediaParent;
import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantReference;
import com.woorisai.testing.WoorisaiPostgresContainer;
import java.time.Clock;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.persistence.autoconfigure.EntityScan;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import org.testcontainers.postgresql.PostgreSQLContainer;

@Tag("postgres")
@SpringBootTest(
        classes = RelationshipConcurrencyPostgresTest.TestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@TestPropertySource(properties = {
        "spring.autoconfigure.exclude="
                + "org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration,"
                + "org.springframework.modulith.events.jpa.JpaEventPublicationAutoConfiguration,"
                + "org.springframework.modulith.events.config.EventPublicationAutoConfiguration",
        "spring.flyway.enabled=true",
        "spring.flyway.locations=classpath:db/migration/postgresql",
        "spring.flyway.default-schema=woorisai",
        "spring.flyway.schemas=woorisai",
        "spring.flyway.create-schemas=true",
        "spring.flyway.baseline-on-migrate=false",
        "spring.jpa.generate-ddl=false",
        "spring.jpa.hibernate.ddl-auto=validate",
        "spring.jpa.properties.hibernate.default_schema=woorisai",
        "spring.jpa.open-in-view=false",
        "spring.sql.init.mode=never"
})
class RelationshipConcurrencyPostgresTest {

    private static final long FIRST = 3_000_000_001L;
    private static final long SECOND = 3_000_000_002L;
    private static final ParticipantReference FIRST_PARTICIPANT =
            new ParticipantReference(FIRST, 1, "Fixture One");
    private static final ParticipantReference SECOND_PARTICIPANT =
            new ParticipantReference(SECOND, 2, "Fixture Two");
    private static final OffsetDateTime NOW = OffsetDateTime.parse("2026-07-21T00:00:00Z");

    @Autowired
    private RelationshipService relationships;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private NoMedia media;

    @Autowired
    private NoParticipants participants;

    @BeforeEach
    void resetDatabase() {
        jdbc.update("DELETE FROM woorisai.media_attachment");
        jdbc.update("DELETE FROM woorisai.score_change_comment");
        jdbc.update("DELETE FROM woorisai.score_change");
        jdbc.update("DELETE FROM woorisai.relationship_score");
        jdbc.update("DELETE FROM woorisai.participant");
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, 1, 'Fixture One', ?), (?, 2, 'Fixture Two', ?)
                """, FIRST, NOW, SECOND, NOW);
        jdbc.update("""
                INSERT INTO woorisai.relationship_score (
                    id, source_participant_id, target_participant_id, current_score, updated_at
                ) VALUES
                    (10, ?, ?, 0, ?),
                    (11, ?, ?, 0, ?)
                """, FIRST, SECOND, NOW, SECOND, FIRST, NOW);
        media.reset();
        participants.reset();
    }

    @Test
    void rejectsOneOverlappingScoreChangeAfterTheOptimisticWinnerCommits()
            throws Exception {
        var executor = Executors.newFixedThreadPool(2);
        try {
            var first = executor.submit(this::plusOne);
            assertThat(media.awaitFirstScoreAttach()).isTrue();

            var second = executor.submit(this::plusOne);
            int firstBackendPid = participants.firstBackendPid();
            int secondBackendPid = participants.awaitSecondBackendPid();
            assertThat(secondBackendPid).isNotEqualTo(firstBackendPid);

            LockObservation lock = awaitLock(firstBackendPid, secondBackendPid);
            assertThat(lock.waitEventType()).isEqualTo("Lock");
            assertThat(lock.blockedByFirst()).isTrue();
            assertThat(second.isDone()).isFalse();
            assertThat(media.secondScoreAttachReached()).isFalse();
            assertThat(first.isDone()).isFalse();
            assertThat(jdbc.queryForObject("""
                    SELECT current_score
                    FROM woorisai.relationship_score
                    WHERE id = 10
                    """, Integer.class)).isZero();
            assertThat(jdbc.queryForObject("""
                    SELECT COUNT(*)
                    FROM woorisai.score_change
                    WHERE relationship_score_id = 10
                    """, Integer.class)).isZero();

            media.releaseFirstScoreAttach();
            List<Object> outcomes = List.of(
                    first.get(5, TimeUnit.SECONDS),
                    second.get(5, TimeUnit.SECONDS));

            assertThat(outcomes).filteredOn(Integer.class::isInstance).containsExactly(1);
            assertThat(outcomes)
                    .filteredOn(RelationshipConflictException.class::isInstance)
                    .hasSize(1);
            assertThat(media.secondScoreAttachReached()).isFalse();
            assertThat(jdbc.queryForObject("""
                    SELECT current_score
                    FROM woorisai.relationship_score
                    WHERE id = 10
                    """, Integer.class)).isEqualTo(1);
            assertThat(jdbc.queryForObject("""
                    SELECT version
                    FROM woorisai.relationship_score
                    WHERE id = 10
                    """, Long.class)).isEqualTo(1L);
            assertThat(jdbc.queryForList("""
                    SELECT resulting_score
                    FROM woorisai.score_change
                    WHERE relationship_score_id = 10
                    ORDER BY resulting_score
                    """, Integer.class)).containsExactly(1);
            assertThat(jdbc.queryForObject("""
                    SELECT COUNT(*)
                    FROM woorisai.score_change
                    WHERE relationship_score_id = 10
                    """, Integer.class)).isEqualTo(1);
        } finally {
            media.releaseFirstScoreAttach();
            executor.shutdownNow();
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }
    }

    private Object plusOne() {
        try {
            return relationships.changeScore(
                            FIRST,
                            ChangeScoreCommand.from(1, null, null, List.of()))
                    .change()
                    .resultingScore();
        } catch (RelationshipConflictException exception) {
            return exception;
        }
    }

    private LockObservation awaitLock(int firstBackendPid, int secondBackendPid)
            throws InterruptedException {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        LockObservation latest = null;
        while (System.nanoTime() < deadline) {
            latest = jdbc.query("""
                    SELECT wait_event_type,
                           ? = ANY(pg_blocking_pids(pid)) AS blocked_by_first
                    FROM pg_stat_activity
                    WHERE pid = ?
                    """, resultSet -> resultSet.next()
                            ? new LockObservation(
                                    resultSet.getString("wait_event_type"),
                                    resultSet.getBoolean("blocked_by_first"))
                            : null,
                    firstBackendPid,
                    secondBackendPid);
            if (latest != null
                    && "Lock".equals(latest.waitEventType())
                    && latest.blockedByFirst()) {
                return latest;
            }
            TimeUnit.MILLISECONDS.sleep(10);
        }
        throw new AssertionError(
                "Second PostgreSQL transaction was not observed waiting on the first; latest="
                        + latest);
    }

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackageClasses = RelationshipScore.class)
    @EnableJpaRepositories(basePackageClasses = RelationshipScoreRepository.class)
    @Import({RelationshipService.class, PostgresBeans.class})
    static class TestApplication {}

    @TestConfiguration(proxyBeanMethods = false)
    static class PostgresBeans {

        @Bean
        Clock clock() {
            return Clock.systemUTC();
        }

        @Bean
        @ServiceConnection
        PostgreSQLContainer postgresContainer() {
            return WoorisaiPostgresContainer.create();
        }

        @Bean
        NoParticipants participantDirectory(JdbcTemplate jdbc) {
            return new NoParticipants(jdbc);
        }

        @Bean
        NoMedia noMedia() {
            return new NoMedia();
        }
    }

    static final class NoParticipants implements ParticipantDirectory {

        private final JdbcTemplate jdbc;
        private final AtomicInteger requests = new AtomicInteger();
        private volatile Integer firstBackendPid;
        private volatile Integer secondBackendPid;
        private CountDownLatch secondBackendPidCaptured = new CountDownLatch(1);

        NoParticipants(JdbcTemplate jdbc) {
            this.jdbc = jdbc;
        }

        @Override
        public CanonicalParticipantPair canonicalPair() {
            Integer backendPid = jdbc.queryForObject("SELECT pg_backend_pid()", Integer.class);
            if (backendPid == null) {
                throw new IllegalStateException("PostgreSQL backend PID was not available");
            }
            int request = requests.incrementAndGet();
            if (request == 1) {
                firstBackendPid = backendPid;
            } else if (request == 2) {
                secondBackendPid = backendPid;
                secondBackendPidCaptured.countDown();
            }
            return new CanonicalParticipantPair(
                    FIRST_PARTICIPANT, SECOND_PARTICIPANT);
        }

        void reset() {
            requests.set(0);
            firstBackendPid = null;
            secondBackendPid = null;
            secondBackendPidCaptured = new CountDownLatch(1);
        }

        int firstBackendPid() {
            Integer captured = firstBackendPid;
            if (captured == null) {
                throw new IllegalStateException("First PostgreSQL backend PID was not captured");
            }
            return captured;
        }

        int awaitSecondBackendPid() throws InterruptedException {
            if (!secondBackendPidCaptured.await(5, TimeUnit.SECONDS)) {
                throw new AssertionError("Second PostgreSQL backend PID was not captured");
            }
            Integer captured = secondBackendPid;
            if (captured == null) {
                throw new AssertionError("Second PostgreSQL backend PID was not available");
            }
            return captured;
        }
    }

    static final class NoMedia implements MediaAttachmentMutation, AttachedMediaQuery {

        private final AtomicInteger scoreAttachAttempts = new AtomicInteger();
        private CountDownLatch firstScoreAttachReached = new CountDownLatch(1);
        private CountDownLatch releaseFirstScoreAttach = new CountDownLatch(1);
        private CountDownLatch secondScoreAttachReached = new CountDownLatch(1);

        @Override
        public void attachScoreChange(AttachScoreChangeMediaCommand command) {
            int attempt = scoreAttachAttempts.incrementAndGet();
            if (attempt == 1) {
                firstScoreAttachReached.countDown();
                await(releaseFirstScoreAttach, "first score attach release", 10);
            } else if (attempt == 2) {
                secondScoreAttachReached.countDown();
            }
        }

        @Override
        public void attachScoreComment(AttachScoreCommentMediaCommand command) {}

        @Override
        public void replaceDiaryEntry(ReplaceDiaryEntryMediaCommand command) {
            throw new UnsupportedOperationException();
        }

        @Override
        public Map<Long, List<AttachedMedia>> attachmentsForScoreChanges(
                List<ScoreChangeMediaParent> parents) {
            Map<Long, List<AttachedMedia>> result = new LinkedHashMap<>();
            parents.forEach(parent -> result.put(parent.scoreChangeId(), List.of()));
            return Map.copyOf(result);
        }

        @Override
        public Map<Long, List<AttachedMedia>> attachmentsForScoreComments(
                List<ScoreCommentMediaParent> parents) {
            Map<Long, List<AttachedMedia>> result = new LinkedHashMap<>();
            parents.forEach(parent -> result.put(parent.scoreCommentId(), List.of()));
            return Map.copyOf(result);
        }

        @Override
        public Map<Long, List<AttachedMedia>> attachmentsForDiaryEntries(
                List<DiaryEntryMediaParent> parents) {
            throw new UnsupportedOperationException();
        }

        void reset() {
            scoreAttachAttempts.set(0);
            firstScoreAttachReached = new CountDownLatch(1);
            releaseFirstScoreAttach = new CountDownLatch(1);
            secondScoreAttachReached = new CountDownLatch(1);
        }

        boolean awaitFirstScoreAttach() throws InterruptedException {
            return firstScoreAttachReached.await(5, TimeUnit.SECONDS);
        }

        boolean awaitSecondScoreAttach() throws InterruptedException {
            return secondScoreAttachReached.await(5, TimeUnit.SECONDS);
        }

        boolean secondScoreAttachReached() {
            return secondScoreAttachReached.getCount() == 0;
        }

        void releaseFirstScoreAttach() {
            releaseFirstScoreAttach.countDown();
        }

        private static void await(CountDownLatch latch, String boundary, long timeoutSeconds) {
            try {
                if (!latch.await(timeoutSeconds, TimeUnit.SECONDS)) {
                    throw new IllegalStateException("Timed out waiting for " + boundary);
                }
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException("Interrupted while waiting for " + boundary, exception);
            }
        }
    }

    private record LockObservation(String waitEventType, boolean blockedByFirst) {}
}
