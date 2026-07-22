package com.woorisai.diary.internal;

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
import java.util.Objects;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Supplier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.persistence.autoconfigure.EntityScan;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.postgresql.PostgreSQLContainer;

@Tag("postgres")
@SpringBootTest(
        classes = DiaryConcurrencyPostgresTest.TestApplication.class,
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
class DiaryConcurrencyPostgresTest {

    private static final long FIRST_ID = 3_000_000_001L;
    private static final long SECOND_ID = 3_000_000_002L;
    private static final long ENTRY_ID = 40L;
    private static final long COMMENT_ID = 50L;
    private static final ParticipantReference FIRST =
            new ParticipantReference(FIRST_ID, 1, "Fixture One");
    private static final ParticipantReference SECOND =
            new ParticipantReference(SECOND_ID, 2, "Fixture Two");
    private static final OffsetDateTime NOW =
            OffsetDateTime.parse("2026-07-21T00:00:00Z");

    @Autowired
    private DiaryService diary;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @Autowired
    private CapturingParticipants participants;

    private TransactionTemplate transactions;

    @BeforeEach
    void resetDatabase() {
        jdbc.update("DELETE FROM woorisai.media_attachment");
        jdbc.update("DELETE FROM woorisai.diary_entry_comment");
        jdbc.update("DELETE FROM woorisai.diary_entry");
        jdbc.update("DELETE FROM woorisai.participant");
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, 1, 'Fixture One', ?), (?, 2, 'Fixture Two', ?)
                """, FIRST_ID, NOW, SECOND_ID, NOW.plusSeconds(1));
        jdbc.update("""
                INSERT INTO woorisai.diary_entry (id, author_id, content, created_at)
                VALUES (?, ?, 'original entry', ?)
                """, ENTRY_ID, FIRST_ID, NOW);
        participants.reset();
        transactions = new TransactionTemplate(transactionManager);
    }

    @Test
    void concurrentCommentsOnTheSameParentCommitWithoutParentWriteSerialization()
            throws Exception {
        CountDownLatch firstFlushed = new CountDownLatch(1);
        CountDownLatch releaseFirst = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            var first = executor.submit(() -> heldTransaction(
                    () -> diary.createComment(
                            FIRST_ID,
                            ENTRY_ID,
                            CreateDiaryCommentCommand.from("first concurrent comment")),
                    firstFlushed,
                    releaseFirst));
            assertThat(firstFlushed.await(5, TimeUnit.SECONDS)).isTrue();

            var second = executor.submit(() -> diary.createComment(
                    SECOND_ID,
                    ENTRY_ID,
                    CreateDiaryCommentCommand.from("second concurrent comment")));

            DiaryEntryCommentCreatedResponse secondResult = second.get(5, TimeUnit.SECONDS);
            assertThat(secondResult.content()).isEqualTo("second concurrent comment");
            assertThat(first.isDone()).isFalse();
            assertThat(commentCount()).isOne();

            releaseFirst.countDown();
            DiaryEntryCommentCreatedResponse firstResult = first.get(5, TimeUnit.SECONDS);

            assertThat(firstResult.content()).isEqualTo("first concurrent comment");
            assertThat(commentCount()).isEqualTo(2);
            assertThat(jdbc.queryForList("""
                    SELECT content
                    FROM woorisai.diary_entry_comment
                    WHERE diary_entry_id = ?
                    """, String.class, ENTRY_ID))
                    .containsExactlyInAnyOrder(
                            "first concurrent comment",
                            "second concurrent comment");
            assertThat(jdbc.queryForList("""
                    SELECT version
                    FROM woorisai.diary_entry_comment
                    WHERE diary_entry_id = ?
                    """, Long.class, ENTRY_ID))
                    .containsOnly(0L);
        } finally {
            releaseFirst.countDown();
            shutdown(executor);
        }
    }

    @Test
    void committedParentDeleteMakesAnOverlappingCommentCreateConflict() throws Exception {
        CountDownLatch deleteFlushed = new CountDownLatch(1);
        CountDownLatch releaseDelete = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            var delete = executor.submit(() -> heldTransaction(() -> {
                diary.deleteEntry(FIRST_ID, ENTRY_ID);
                return Completed.INSTANCE;
            }, deleteFlushed, releaseDelete));
            assertThat(deleteFlushed.await(5, TimeUnit.SECONDS)).isTrue();

            var create = executor.submit(() -> outcome(() -> diary.createComment(
                    SECOND_ID,
                    ENTRY_ID,
                    CreateDiaryCommentCommand.from("too late"))));
            int deleteBackendPid = participants.firstBackendPid();
            int createBackendPid = participants.awaitSecondBackendPid();
            LockObservation lock = awaitLock(deleteBackendPid, createBackendPid);

            assertThat(lock.waitEventType()).isEqualTo("Lock");
            assertThat(lock.blockedByFirst()).isTrue();
            assertThat(create.isDone()).isFalse();

            releaseDelete.countDown();
            assertThat(delete.get(5, TimeUnit.SECONDS)).isEqualTo(Completed.INSTANCE);
            assertThat(create.get(5, TimeUnit.SECONDS)).isInstanceOf(DiaryConflictException.class);
            assertThat(jdbc.queryForObject(
                    "SELECT COUNT(*) FROM woorisai.diary_entry WHERE id = ?",
                    Long.class,
                    ENTRY_ID)).isZero();
            assertThat(commentCount()).isZero();
        } finally {
            releaseDelete.countDown();
            shutdown(executor);
        }
    }

    @Test
    void committedEntryUpdateMakesAnOverlappingDeleteConflict() throws Exception {
        CountDownLatch updateFlushed = new CountDownLatch(1);
        CountDownLatch releaseUpdate = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            var update = executor.submit(() -> heldTransaction(
                    () -> diary.updateEntry(
                            FIRST_ID,
                            ENTRY_ID,
                            UpdateDiaryEntryCommand.from("updated entry", null)),
                    updateFlushed,
                    releaseUpdate));
            assertThat(updateFlushed.await(5, TimeUnit.SECONDS)).isTrue();

            var delete = executor.submit(
                    () -> outcome(() -> diary.deleteEntry(FIRST_ID, ENTRY_ID)));
            int updateBackendPid = participants.firstBackendPid();
            int deleteBackendPid = participants.awaitSecondBackendPid();
            LockObservation lock = awaitLock(updateBackendPid, deleteBackendPid);

            assertThat(lock.waitEventType()).isEqualTo("Lock");
            assertThat(lock.blockedByFirst()).isTrue();
            assertThat(delete.isDone()).isFalse();

            releaseUpdate.countDown();
            DiaryEntryUpdatedResponse updated = update.get(5, TimeUnit.SECONDS);
            Object deleteOutcome = delete.get(5, TimeUnit.SECONDS);

            assertThat(updated.content()).isEqualTo("updated entry");
            assertThat(deleteOutcome).isInstanceOf(DiaryConflictException.class);
            assertThat(jdbc.queryForMap("""
                    SELECT content, version
                    FROM woorisai.diary_entry
                    WHERE id = ?
                    """, ENTRY_ID))
                    .containsEntry("content", "updated entry")
                    .containsEntry("version", 1L);
        } finally {
            releaseUpdate.countDown();
            shutdown(executor);
        }
    }

    @Test
    void committedCommentUpdateMakesAnOverlappingDeleteConflict() throws Exception {
        insertComment();
        CountDownLatch updateFlushed = new CountDownLatch(1);
        CountDownLatch releaseUpdate = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            var update = executor.submit(() -> heldTransaction(
                    () -> diary.updateComment(
                            FIRST_ID,
                            COMMENT_ID,
                            UpdateDiaryCommentCommand.from("updated comment")),
                    updateFlushed,
                    releaseUpdate));
            assertThat(updateFlushed.await(5, TimeUnit.SECONDS)).isTrue();

            var delete = executor.submit(
                    () -> outcome(() -> diary.deleteComment(FIRST_ID, COMMENT_ID)));
            int updateBackendPid = participants.firstBackendPid();
            int deleteBackendPid = participants.awaitSecondBackendPid();
            LockObservation lock = awaitLock(updateBackendPid, deleteBackendPid);

            assertThat(lock.waitEventType()).isEqualTo("Lock");
            assertThat(lock.blockedByFirst()).isTrue();
            assertThat(delete.isDone()).isFalse();

            releaseUpdate.countDown();
            DiaryEntryCommentUpdatedResponse updated = update.get(5, TimeUnit.SECONDS);
            Object deleteOutcome = delete.get(5, TimeUnit.SECONDS);

            assertThat(updated.content()).isEqualTo("updated comment");
            assertThat(deleteOutcome).isInstanceOf(DiaryConflictException.class);
            assertThat(jdbc.queryForMap("""
                    SELECT content, version
                    FROM woorisai.diary_entry_comment
                    WHERE id = ?
                    """, COMMENT_ID))
                    .containsEntry("content", "updated comment")
                    .containsEntry("version", 1L);
        } finally {
            releaseUpdate.countDown();
            shutdown(executor);
        }
    }

    private <T> T heldTransaction(
            Supplier<T> operation,
            CountDownLatch flushed,
            CountDownLatch release) {
        T result = transactions.execute(status -> {
            T completed = operation.get();
            flushed.countDown();
            await(release, "held transaction release");
            return completed;
        });
        return Objects.requireNonNull(result, "held transaction result");
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

    private void insertComment() {
        jdbc.update("""
                INSERT INTO woorisai.diary_entry_comment (
                    id, diary_entry_id, author_id, content, created_at
                ) VALUES (?, ?, ?, 'original comment', ?)
                """, COMMENT_ID, ENTRY_ID, FIRST_ID, NOW.plusSeconds(1));
    }

    private long commentCount() {
        return jdbc.queryForObject("""
                SELECT COUNT(*)
                FROM woorisai.diary_entry_comment
                WHERE diary_entry_id = ?
                """, Long.class, ENTRY_ID);
    }

    private static Object outcome(Runnable operation) {
        try {
            operation.run();
            return Completed.INSTANCE;
        } catch (RuntimeException exception) {
            return exception;
        }
    }

    private static void await(CountDownLatch latch, String boundary) {
        try {
            if (!latch.await(10, TimeUnit.SECONDS)) {
                throw new IllegalStateException("Timed out waiting for " + boundary);
            }
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while waiting for " + boundary, exception);
        }
    }

    private static void shutdown(ExecutorService executor) throws InterruptedException {
        executor.shutdownNow();
        assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
    }

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackageClasses = DiaryEntry.class)
    @EnableJpaRepositories(basePackageClasses = DiaryEntryRepository.class)
    @Import({DiaryService.class, PostgresBeans.class})
    static class TestApplication {}

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
        CapturingParticipants participantDirectory(JdbcTemplate jdbc) {
            return new CapturingParticipants(jdbc);
        }

        @Bean
        NoMedia noMedia() {
            return new NoMedia();
        }
    }

    static final class CapturingParticipants implements ParticipantDirectory {

        private final JdbcTemplate jdbc;
        private final AtomicInteger requests = new AtomicInteger();
        private volatile Integer firstBackendPid;
        private volatile Integer secondBackendPid;
        private CountDownLatch secondBackendPidCaptured = new CountDownLatch(1);

        CapturingParticipants(JdbcTemplate jdbc) {
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
            return new CanonicalParticipantPair(FIRST, SECOND);
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

        @Override
        public void attachScoreChange(AttachScoreChangeMediaCommand command) {
            throw new UnsupportedOperationException();
        }

        @Override
        public void attachScoreComment(AttachScoreCommentMediaCommand command) {
            throw new UnsupportedOperationException();
        }

        @Override
        public void replaceDiaryEntry(ReplaceDiaryEntryMediaCommand command) {}

        @Override
        public Map<Long, List<AttachedMedia>> attachmentsForScoreChanges(
                List<ScoreChangeMediaParent> parents) {
            throw new UnsupportedOperationException();
        }

        @Override
        public Map<Long, List<AttachedMedia>> attachmentsForScoreComments(
                List<ScoreCommentMediaParent> parents) {
            throw new UnsupportedOperationException();
        }

        @Override
        public Map<Long, List<AttachedMedia>> attachmentsForDiaryEntries(
                List<DiaryEntryMediaParent> parents) {
            Map<Long, List<AttachedMedia>> result = new LinkedHashMap<>();
            parents.forEach(parent -> result.put(parent.diaryEntryId(), List.of()));
            return Map.copyOf(result);
        }
    }

    private enum Completed {
        INSTANCE
    }

    private record LockObservation(String waitEventType, boolean blockedByFirst) {}
}
