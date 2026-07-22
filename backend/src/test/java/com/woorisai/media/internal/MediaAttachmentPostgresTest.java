package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThat;

import com.woorisai.media.AttachScoreCommentMediaCommand;
import com.woorisai.media.MediaAttachmentMutation;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentConflictException;
import com.woorisai.media.ReplaceDiaryEntryMediaCommand;
import com.woorisai.testing.WoorisaiPostgresContainer;
import java.net.URI;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
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
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.postgresql.PostgreSQLContainer;

@Tag("postgres")
@SpringBootTest(
        classes = MediaAttachmentPostgresTest.TestApplication.class,
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
class MediaAttachmentPostgresTest {

    private static final long FIRST = 3_000_000_001L;
    private static final long SECOND = 3_000_000_002L;
    private static final OffsetDateTime NOW = OffsetDateTime.parse("2026-07-21T00:00:00Z");
    private static final String DISCARD_CONTENDER = "media-discard-contender";
    private static final String COMPLETE_CONTENDER = "media-complete-contender";

    @Autowired
    private MediaAttachmentMutation mutation;

    @Autowired
    private TransactionTemplate transactions;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private MediaService media;

    @Autowired
    private BlockingMediaObjectStorage objects;

    @BeforeEach
    void resetDatabase() {
        objects.reset();
        jdbc.update("DELETE FROM woorisai.media_attachment");
        jdbc.update("DELETE FROM woorisai.diary_entry_comment");
        jdbc.update("DELETE FROM woorisai.diary_entry");
        jdbc.update("DELETE FROM woorisai.score_change_comment");
        jdbc.update("DELETE FROM woorisai.score_change");
        jdbc.update("DELETE FROM woorisai.relationship_score");
        jdbc.update("DELETE FROM woorisai.participant");
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, 1, 'Fixture One', ?), (?, 2, 'Fixture Two', ?)
                """, FIRST, NOW, SECOND, NOW);
    }

    @Test
    void completeAndDiscardAreSerializedByThePostgresUploadRowLock() throws Exception {
        UUID upload = UUID.fromString("20000000-0000-4000-8000-000000000004");
        insertPending(upload);

        var discardStarted = new CountDownLatch(1);
        var executor = Executors.newFixedThreadPool(2);
        try {
            var completion = executor.submit(() -> completeAttempt(upload));
            assertThat(objects.awaitPendingInspection()).isTrue();

            var discard = executor.submit(() -> {
                try {
                    transactions.executeWithoutResult(ignored -> {
                        nameCurrentTransaction(DISCARD_CONTENDER);
                        discardStarted.countDown();
                        media.discard(FIRST, upload);
                    });
                    return null;
                } catch (Throwable failure) {
                    return failure;
                }
            });

            assertThat(discardStarted.await(5, TimeUnit.SECONDS)).isTrue();
            assertThat(awaitPostgresLockWait(DISCARD_CONTENDER))
                    .as("discard must wait on PostgreSQL while complete owns the upload row lock")
                    .isTrue();

            objects.releasePendingInspection();

            assertThat(completion.get(5, TimeUnit.SECONDS)).isNull();
            assertThat(discard.get(5, TimeUnit.SECONDS)).isNull();
            assertThat(jdbc.queryForObject("""
                    SELECT COUNT(*)
                    FROM woorisai.media_attachment
                    WHERE id = ?
                    """, Integer.class, upload)).isZero();
            assertThat(objects.copies()).containsExactly(
                    "pending/" + upload + "->media/" + upload);
            assertThat(objects.deletes()).containsExactlyInAnyOrder(
                    "pending/" + upload,
                    "media/" + upload);
        } finally {
            objects.releasePendingInspection();
            executor.shutdownNow();
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }
    }

    @Test
    void discardCommitMakesAWaitingCompleteFailBeforeAnyStorageCopy() throws Exception {
        UUID upload = UUID.fromString("20000000-0000-4000-8000-000000000005");
        insertPending(upload);

        var discardHasDeleted = new CountDownLatch(1);
        var allowDiscardCommit = new CountDownLatch(1);
        var completeStarted = new CountDownLatch(1);
        var executor = Executors.newFixedThreadPool(2);
        try {
            var discard = executor.submit(() -> {
                try {
                    transactions.executeWithoutResult(ignored -> {
                        media.discard(FIRST, upload);
                        discardHasDeleted.countDown();
                        await(allowDiscardCommit, "discard commit release", 15);
                    });
                    return null;
                } catch (Throwable failure) {
                    return failure;
                }
            });
            assertThat(discardHasDeleted.await(5, TimeUnit.SECONDS)).isTrue();

            var completion = executor.submit(() -> {
                try {
                    return transactions.execute(ignored -> {
                        nameCurrentTransaction(COMPLETE_CONTENDER);
                        completeStarted.countDown();
                        media.complete(FIRST, upload);
                        return null;
                    });
                } catch (Throwable failure) {
                    return failure;
                }
            });
            assertThat(completeStarted.await(5, TimeUnit.SECONDS)).isTrue();
            assertThat(awaitPostgresLockWait(COMPLETE_CONTENDER))
                    .as("complete must wait on PostgreSQL until discard commits")
                    .isTrue();
            assertThat(objects.copies()).isEmpty();

            allowDiscardCommit.countDown();

            assertThat(discard.get(5, TimeUnit.SECONDS)).isNull();
            assertThat(completion.get(5, TimeUnit.SECONDS))
                    .isInstanceOf(MediaUploadNotFoundException.class);
            assertThat(objects.copies()).isEmpty();
            assertThat(objects.deletes()).containsExactly("pending/" + upload);
            assertThat(jdbc.queryForObject("""
                    SELECT COUNT(*)
                    FROM woorisai.media_attachment
                    WHERE id = ?
                    """, Integer.class, upload)).isZero();
        } finally {
            allowDiscardCommit.countDown();
            objects.releasePendingInspection();
            executor.shutdownNow();
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }
    }

    @Test
    void theSameReadyUploadHasExactlyOneConcurrentAttachWinner() throws Exception {
        insertScoreCommentGraph();
        UUID upload = UUID.fromString("20000000-0000-4000-8000-000000000001");
        insertReady(upload, "SCORE_CHANGE_COMMENT", null, null, null, 0);

        var start = new CyclicBarrier(2);
        Callable<Throwable> first = attachAttempt(start, upload, 30L);
        Callable<Throwable> second = attachAttempt(start, upload, 31L);
        var executor = Executors.newFixedThreadPool(2);
        try {
            var outcomes = executor.invokeAll(List.of(first, second), 10, TimeUnit.SECONDS)
                    .stream()
                    .map(future -> {
                        try {
                            return future.get(1, TimeUnit.SECONDS);
                        } catch (Exception exception) {
                            return exception;
                        }
                    })
                    .toList();

            assertThat(outcomes).filteredOn(outcome -> outcome == null).hasSize(1);
            assertThat(outcomes).filteredOn(MediaAttachmentConflictException.class::isInstance)
                    .hasSize(1);
            assertThat(jdbc.queryForObject("""
                    SELECT score_change_comment_id
                    FROM woorisai.media_attachment
                    WHERE id = ?
                    """, Long.class, upload)).isIn(30L, 31L);
        } finally {
            executor.shutdownNow();
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }
    }

    @Test
    void diaryReorderingDoesNotTripTheUniqueParentPositionIndex() {
        jdbc.update("""
                INSERT INTO woorisai.diary_entry (id, author_id, content, created_at)
                VALUES (40, ?, 'fixture diary', ?)
                """, FIRST, NOW);
        UUID first = UUID.fromString("20000000-0000-4000-8000-000000000002");
        UUID second = UUID.fromString("20000000-0000-4000-8000-000000000003");
        insertReady(first, "DIARY_ENTRY", null, null, 40L, 0);
        insertReady(second, "DIARY_ENTRY", null, null, 40L, 1);

        transactions.executeWithoutResult(ignored -> mutation.replaceDiaryEntry(
                new ReplaceDiaryEntryMediaCommand(FIRST, 40L, List.of(second, first))));

        assertThat(jdbc.query("""
                SELECT id || ':' || position
                FROM woorisai.media_attachment
                WHERE diary_entry_id = 40
                ORDER BY position
                """, (result, rowNumber) -> result.getString(1)))
                .containsExactly(second + ":0", first + ":1");
    }

    private Callable<Throwable> attachAttempt(
            CyclicBarrier start,
            UUID upload,
            long commentId) {
        return () -> {
            start.await(5, TimeUnit.SECONDS);
            try {
                transactions.executeWithoutResult(ignored -> mutation.attachScoreComment(
                        new AttachScoreCommentMediaCommand(
                                FIRST, commentId, List.of(upload))));
                return null;
            } catch (Throwable failure) {
                return failure;
            }
        };
    }

    private Throwable completeAttempt(UUID upload) {
        try {
            return transactions.execute(ignored -> {
                media.complete(FIRST, upload);
                return null;
            });
        } catch (Throwable failure) {
            return failure;
        }
    }

    private void nameCurrentTransaction(String applicationName) {
        jdbc.queryForObject(
                "SELECT set_config('application_name', ?, true)",
                String.class,
                applicationName);
    }

    private boolean awaitPostgresLockWait(String applicationName) throws InterruptedException {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (System.nanoTime() < deadline) {
            Boolean waiting = jdbc.queryForObject("""
                    SELECT EXISTS (
                        SELECT 1
                        FROM pg_stat_activity
                        WHERE application_name = ?
                          AND wait_event_type = 'Lock'
                    )
                    """, Boolean.class, applicationName);
            if (Boolean.TRUE.equals(waiting)) {
                return true;
            }
            TimeUnit.MILLISECONDS.sleep(25);
        }
        return false;
    }

    private static void await(CountDownLatch latch, String description, long timeoutSeconds) {
        try {
            if (!latch.await(timeoutSeconds, TimeUnit.SECONDS)) {
                throw new IllegalStateException("Timed out waiting for " + description);
            }
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while waiting for " + description, exception);
        }
    }

    private void insertScoreCommentGraph() {
        jdbc.update("""
                INSERT INTO woorisai.relationship_score (
                    id, source_participant_id, target_participant_id, current_score, updated_at
                ) VALUES (10, ?, ?, 50, ?)
                """, FIRST, SECOND, NOW);
        jdbc.update("""
                INSERT INTO woorisai.score_change (
                    id, relationship_score_id, changed_by_id, delta,
                    resulting_score, reason, created_at
                ) VALUES (20, 10, ?, 1, 51, NULL, ?)
                """, FIRST, NOW);
        jdbc.update("""
                INSERT INTO woorisai.score_change_comment (
                    id, score_change_id, author_id, content, created_at
                ) VALUES
                    (30, 20, ?, 'first', ?),
                    (31, 20, ?, 'second', ?)
                """, FIRST, NOW, FIRST, NOW);
    }

    private void insertReady(
            UUID id,
            String purpose,
            Long scoreChangeId,
            Long scoreCommentId,
            Long diaryEntryId,
            int position) {
        jdbc.update("""
                INSERT INTO woorisai.media_attachment (
                    id, uploader_id, score_change_id, score_change_comment_id, diary_entry_id,
                    purpose, kind, status, object_key, original_name, content_type,
                    expected_size, actual_size, position, created_at, ready_at
                ) VALUES (?, ?, ?, ?, ?, ?, 'IMAGE', 'READY', ?, 'fixture.png',
                    'image/png', 8, 8, ?, ?, ?)
                """,
                id,
                FIRST,
                scoreChangeId,
                scoreCommentId,
                diaryEntryId,
                purpose,
                "media/" + id,
                position,
                NOW,
                NOW.plus(Duration.ofMinutes(1)));
    }

    private void insertPending(UUID id) {
        jdbc.update("""
                INSERT INTO woorisai.media_attachment (
                    id, uploader_id, score_change_id, score_change_comment_id, diary_entry_id,
                    purpose, kind, status, object_key, original_name, content_type,
                    expected_size, actual_size, position, created_at, ready_at
                ) VALUES (?, ?, NULL, NULL, NULL, 'DIARY_ENTRY', 'IMAGE', 'PENDING', ?,
                    'fixture.png', 'image/png', 8, NULL, 0, ?, NULL)
                """, id, FIRST, "pending/" + id, NOW);
    }

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackageClasses = MediaAttachment.class)
    @EnableJpaRepositories(basePackageClasses = MediaAttachmentRepository.class)
    @Import({
        MediaAttachmentMutationService.class,
        MediaServiceConfiguration.class,
        PostgresConfiguration.class
    })
    static class TestApplication {}

    @TestConfiguration(proxyBeanMethods = false)
    static class MediaServiceConfiguration {

        @Bean
        BlockingMediaObjectStorage mediaObjectStorage() {
            return new BlockingMediaObjectStorage();
        }

        @Bean
        MediaService mediaService(
                MediaAttachmentRepository attachments,
                BlockingMediaObjectStorage objects) {
            return new MediaService(
                    attachments,
                    objects,
                    new MediaPolicy(900),
                    300,
                    Clock.fixed(Instant.parse("2026-07-21T00:00:00Z"), ZoneOffset.UTC),
                    UUID::randomUUID);
        }
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class PostgresConfiguration {

        @Bean
        @ServiceConnection
        PostgreSQLContainer postgresContainer() {
            return WoorisaiPostgresContainer.create();
        }
    }

    static final class BlockingMediaObjectStorage implements MediaObjectStorage {

        private static final byte[] PNG = new byte[] {
                (byte) 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a
        };

        private volatile CountDownLatch pendingInspectionStarted = new CountDownLatch(1);
        private volatile CountDownLatch allowPendingInspection = new CountDownLatch(1);
        private final ConcurrentLinkedQueue<String> copies = new ConcurrentLinkedQueue<>();
        private final ConcurrentLinkedQueue<String> deletes = new ConcurrentLinkedQueue<>();

        void reset() {
            pendingInspectionStarted = new CountDownLatch(1);
            allowPendingInspection = new CountDownLatch(1);
            copies.clear();
            deletes.clear();
        }

        boolean awaitPendingInspection() throws InterruptedException {
            return pendingInspectionStarted.await(5, TimeUnit.SECONDS);
        }

        void releasePendingInspection() {
            allowPendingInspection.countDown();
        }

        List<String> copies() {
            return List.copyOf(copies);
        }

        List<String> deletes() {
            return List.copyOf(deletes);
        }

        @Override
        public URI presignUpload(UploadPresignRequest request) {
            throw new UnsupportedOperationException();
        }

        @Override
        public StoredMediaObject inspect(String objectKey) {
            if (objectKey.startsWith("pending/")) {
                pendingInspectionStarted.countDown();
                try {
                    if (!allowPendingInspection.await(15, TimeUnit.SECONDS)) {
                        throw new IllegalStateException("Timed out waiting to inspect pending media");
                    }
                } catch (InterruptedException exception) {
                    Thread.currentThread().interrupt();
                    throw new IllegalStateException("Pending media inspection was interrupted", exception);
                }
            }
            return new StoredMediaObject(PNG.length, "image/png", PNG);
        }

        @Override
        public void copy(MediaObjectCopy request) {
            copies.add(request.sourceKey() + "->" + request.destinationKey());
        }

        @Override
        public URI presignDownload(DownloadPresignRequest request) {
            throw new UnsupportedOperationException();
        }

        @Override
        public void delete(String objectKey) {
            deletes.add(objectKey);
        }
    }
}
