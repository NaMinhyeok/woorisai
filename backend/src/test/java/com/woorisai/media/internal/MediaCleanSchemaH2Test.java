package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.media.AttachScoreCommentMediaCommand;
import com.woorisai.media.AttachedMediaQuery;
import com.woorisai.media.MediaAttachmentMutation;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentConflictException;
import com.woorisai.media.MediaKind;
import com.woorisai.media.ReplaceDiaryEntryMediaCommand;
import com.woorisai.media.ScoreCommentMediaParent;
import java.net.URI;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.persistence.autoconfigure.EntityScan;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import org.springframework.transaction.IllegalTransactionStateException;
import org.springframework.transaction.support.TransactionTemplate;

@SpringBootTest(
        classes = MediaCleanSchemaH2Test.TestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@TestPropertySource(
        locations = "classpath:clean-schema-h2.properties",
        properties = {
            "spring.autoconfigure.exclude="
                + "org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration,"
                + "org.springframework.modulith.events.jpa.JpaEventPublicationAutoConfiguration,"
                + "org.springframework.modulith.events.config.EventPublicationAutoConfiguration",
            "spring.datasource.url=jdbc:h2:mem:media-clean-schema;"
                + "MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;"
                + "DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE"
})
class MediaCleanSchemaH2Test {

    private static final long FIRST = 3_000_000_001L;
    private static final long SECOND = 3_000_000_002L;
    private static final byte[] PNG = new byte[] {
            (byte) 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a
    };
    private static final Instant NOW = Instant.parse("2026-07-21T00:00:00Z");

    @Autowired
    private MediaService media;

    @Autowired
    private MediaAttachmentMutation mutation;

    @Autowired
    private AttachedMediaQuery query;

    @Autowired
    private FakeMediaObjectStorage objects;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private TransactionTemplate transactions;

    @BeforeEach
    void resetDatabase() {
        jdbc.update("DELETE FROM woorisai.media_attachment");
        jdbc.update("DELETE FROM woorisai.diary_entry_comment");
        jdbc.update("DELETE FROM woorisai.diary_entry");
        jdbc.update("DELETE FROM woorisai.score_change_comment");
        jdbc.update("DELETE FROM woorisai.score_change");
        jdbc.update("DELETE FROM woorisai.relationship_score");
        jdbc.update("DELETE FROM woorisai.participant_credential");
        jdbc.update("DELETE FROM woorisai.participant");
        objects.reset();
        insertParticipant(FIRST, 1, "Fixture One");
        insertParticipant(SECOND, 2, "Fixture Two");
    }

    @Test
    void completesOnceAttachesQueriesAndDownloadsACommentImage() {
        insertScoreCommentGraph();
        var initiated = initiateImage(
                FIRST, MediaPurpose.SCORE_CHANGE_COMMENT, "comment.png");

        assertThat(initiated.uploadUrl().toString()).contains("/pending/" + initiated.uploadId());
        assertThat(row(initiated.uploadId()))
                .containsExactly("PENDING", "pending/" + initiated.uploadId(), null, null);

        objects.put("pending/" + initiated.uploadId(), "image/png", PNG);
        var completed = media.complete(FIRST, initiated.uploadId());

        assertThat(completed.byteSize()).isEqualTo(PNG.length);
        assertThat(objects.inspectedKeys()).containsExactly(
                "pending/" + initiated.uploadId(),
                "media/" + initiated.uploadId());
        assertThat(objects.copies()).containsExactly(new MediaObjectCopy(
                "pending/" + initiated.uploadId(),
                "media/" + initiated.uploadId(),
                "image/png",
                "comment.png"));
        assertThat(row(initiated.uploadId()))
                .containsExactly("READY", "media/" + initiated.uploadId(), (long) PNG.length, null);

        int inspections = objects.inspectedKeys().size();
        assertThat(media.complete(FIRST, initiated.uploadId()))
                .isEqualTo(completed);
        assertThat(objects.inspectedKeys()).hasSize(inspections);

        assertThatThrownBy(() -> media.download(SECOND, initiated.uploadId()))
                .isInstanceOf(MediaAttachmentNotFoundException.class);

        transactions.executeWithoutResult(ignored -> mutation.attachScoreComment(
                new AttachScoreCommentMediaCommand(
                        FIRST, 30L, List.of(initiated.uploadId()))));

        assertThat(query.attachmentsForScoreComments(List.of(
                new ScoreCommentMediaParent(30L, FIRST))).get(30L))
                .singleElement()
                .satisfies(media -> {
                    assertThat(media.id()).isEqualTo(initiated.uploadId());
                    assertThat(media.byteSize()).isEqualTo(PNG.length);
                });
        assertThat(media.download(SECOND, initiated.uploadId()).downloadUrl().toString())
                .contains("/media/" + initiated.uploadId());
        assertThatThrownBy(() -> media.discard(FIRST, initiated.uploadId()))
                .isInstanceOf(MediaUploadDiscardConflictException.class);
    }

    @Test
    void rejectedContentLeavesPendingSoTheSameUploadCanBeRetried() {
        var initiated = initiateImage(FIRST, MediaPurpose.DIARY_ENTRY, "retry.png");
        objects.put("pending/" + initiated.uploadId(), "image/png", new byte[PNG.length]);

        assertThatThrownBy(() -> media.complete(FIRST, initiated.uploadId()))
                .isInstanceOf(MediaUploadContentRejectedException.class);
        assertThat(row(initiated.uploadId())).first().isEqualTo("PENDING");

        objects.put("pending/" + initiated.uploadId(), "image/png", PNG);
        assertThat(media.complete(FIRST, initiated.uploadId()).uploadId())
                .isEqualTo(initiated.uploadId());
        assertThat(row(initiated.uploadId())).first().isEqualTo("READY");
    }

    @Test
    void completionDeletesTheStagingObjectOnlyAfterItsDatabaseTransactionCommits() {
        var initiated = initiateImage(
                FIRST, MediaPurpose.DIARY_ENTRY, "transaction.png");
        String stagingKey = "pending/" + initiated.uploadId();
        objects.put(stagingKey, "image/png", PNG);

        transactions.executeWithoutResult(status -> {
            media.complete(FIRST, initiated.uploadId());
            assertThat(objects.deletedKeys()).isEmpty();
            status.setRollbackOnly();
        });

        assertThat(row(initiated.uploadId())).first().isEqualTo("PENDING");
        assertThat(objects.deletedKeys()).isEmpty();
        assertThat(objects.contains(stagingKey)).isTrue();

        media.complete(FIRST, initiated.uploadId());

        assertThat(row(initiated.uploadId())).first().isEqualTo("READY");
        assertThat(objects.deletedKeys()).containsExactly(stagingKey);
        assertThat(objects.contains(stagingKey)).isFalse();
    }

    @Test
    void stagingDeleteFailureDoesNotRollBackACompletedUpload() {
        var initiated = initiateImage(
                FIRST, MediaPurpose.DIARY_ENTRY, "orphan-accepted.png");
        String stagingKey = "pending/" + initiated.uploadId();
        objects.put(stagingKey, "image/png", PNG);
        objects.failDeletes = true;

        assertThat(media.complete(FIRST, initiated.uploadId()).uploadId())
                .isEqualTo(initiated.uploadId());

        assertThat(row(initiated.uploadId())).first().isEqualTo("READY");
        assertThat(objects.deletedKeys()).containsExactly(stagingKey);
        assertThat(objects.contains(stagingKey)).isTrue();
    }

    @Test
    void diaryReplacementDetachesBeforeReorderingAndDeletesOmittedRows() {
        jdbc.update("""
                INSERT INTO woorisai.diary_entry (id, author_id, content, created_at)
                VALUES (40, ?, 'fixture diary', CAST(? AS TIMESTAMP WITH TIME ZONE))
                """, FIRST, NOW.toString());
        UUID first = readyImage(MediaPurpose.DIARY_ENTRY, "first.png");
        UUID second = readyImage(MediaPurpose.DIARY_ENTRY, "second.png");

        transactions.executeWithoutResult(ignored -> mutation.replaceDiaryEntry(
                new ReplaceDiaryEntryMediaCommand(FIRST, 40L, List.of(first, second))));
        transactions.executeWithoutResult(ignored -> mutation.replaceDiaryEntry(
                new ReplaceDiaryEntryMediaCommand(FIRST, 40L, List.of(second, first))));

        assertThat(attachedDiaryRows(40L)).containsExactly(
                second + ":0",
                first + ":1");

        transactions.executeWithoutResult(ignored -> mutation.replaceDiaryEntry(
                new ReplaceDiaryEntryMediaCommand(FIRST, 40L, List.of(second))));
        assertThat(attachedDiaryRows(40L)).containsExactly(second + ":0");
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.media_attachment WHERE id = ?",
                Integer.class,
                first)).isZero();
    }

    @Test
    void mutationRequiresTheCallerTransactionAndDiscardDeletesRowsBeforeBestEffortObjects() {
        UUID upload = readyImage(MediaPurpose.SCORE_CHANGE_COMMENT, "standalone.png");
        assertThat(objects.deletedKeys()).containsExactly("pending/" + upload);

        assertThatThrownBy(() -> mutation.attachScoreComment(
                new AttachScoreCommentMediaCommand(FIRST, 30L, List.of(upload))))
                .isInstanceOf(IllegalTransactionStateException.class);

        media.discard(FIRST, upload);
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.media_attachment WHERE id = ?",
                Integer.class,
                upload)).isZero();
        assertThat(objects.deletedKeys()).containsExactly(
                "pending/" + upload,
                "media/" + upload);

        UUID pending = initiateImage(
                FIRST, MediaPurpose.DIARY_ENTRY, "pending.png").uploadId();
        objects.failDeletes = true;
        media.discard(FIRST, pending);
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.media_attachment WHERE id = ?",
                Integer.class,
                pending)).isZero();
    }

    private UUID readyImage(MediaPurpose purpose, String name) {
        var initiated = initiateImage(FIRST, purpose, name);
        objects.put("pending/" + initiated.uploadId(), "image/png", PNG);
        media.complete(FIRST, initiated.uploadId());
        return initiated.uploadId();
    }

    private InitiatedMediaUpload initiateImage(
            long uploader,
            MediaPurpose purpose,
            String name) {
        return media.initiate(
                uploader,
                purpose,
                MediaKind.IMAGE,
                name,
                "image/png",
                PNG.length);
    }

    private void insertParticipant(long id, int slot, String name) {
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, ?, ?, CAST(? AS TIMESTAMP WITH TIME ZONE))
                """, id, slot, name, NOW.toString());
    }

    private void insertScoreCommentGraph() {
        jdbc.update("""
                INSERT INTO woorisai.relationship_score (
                    id, source_participant_id, target_participant_id, current_score, updated_at
                ) VALUES (10, ?, ?, 50, CAST(? AS TIMESTAMP WITH TIME ZONE))
                """, FIRST, SECOND, NOW.toString());
        jdbc.update("""
                INSERT INTO woorisai.score_change (
                    id, relationship_score_id, changed_by_id, delta,
                    resulting_score, reason, created_at
                ) VALUES (20, 10, ?, 1, 51, NULL, CAST(? AS TIMESTAMP WITH TIME ZONE))
                """, FIRST, NOW.toString());
        jdbc.update("""
                INSERT INTO woorisai.score_change_comment (
                    id, score_change_id, author_id, content, created_at
                ) VALUES (30, 20, ?, 'fixture comment', CAST(? AS TIMESTAMP WITH TIME ZONE))
                """, FIRST, NOW.toString());
    }

    private List<Object> row(UUID id) {
        return jdbc.queryForObject("""
                SELECT status, object_key, actual_size, score_change_comment_id
                FROM woorisai.media_attachment
                WHERE id = ?
                """, (result, rowNumber) -> Arrays.asList(
                        result.getString("status"),
                        result.getString("object_key"),
                        result.getObject("actual_size", Long.class),
                        result.getObject("score_change_comment_id", Long.class)), id);
    }

    private List<String> attachedDiaryRows(long diaryEntryId) {
        return jdbc.query("""
                SELECT id, position
                FROM woorisai.media_attachment
                WHERE diary_entry_id = ?
                ORDER BY position
                """, (result, rowNumber) -> result.getObject("id") + ":" + result.getInt("position"),
                diaryEntryId);
    }

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackageClasses = MediaAttachment.class)
    @EnableJpaRepositories(basePackageClasses = MediaAttachmentRepository.class)
    @Import({AttachedMediaQueryService.class, MediaAttachmentMutationService.class, TestBeans.class})
    static class TestApplication {}

    @TestConfiguration(proxyBeanMethods = false)
    static class TestBeans {

        @Bean
        FakeMediaObjectStorage fakeMediaObjectStorage() {
            return new FakeMediaObjectStorage();
        }

        @Bean
        MediaService mediaService(
                MediaAttachmentRepository attachments,
                FakeMediaObjectStorage objects) {
            AtomicInteger ids = new AtomicInteger(1);
            return new MediaService(
                    attachments,
                    objects,
                    new MediaPolicy(900),
                    300,
                    Clock.fixed(NOW, ZoneOffset.UTC),
                    () -> UUID.fromString("10000000-0000-4000-8000-%012d".formatted(ids.getAndIncrement())));
        }
    }

    static final class FakeMediaObjectStorage implements MediaObjectStorage {

        private final Map<String, StoredMediaObject> stored = new LinkedHashMap<>();
        private final List<String> inspected = new ArrayList<>();
        private final List<MediaObjectCopy> copied = new ArrayList<>();
        private final List<String> deleted = new ArrayList<>();
        private boolean failDeletes;

        @Override
        public URI presignUpload(UploadPresignRequest request) {
            return URI.create("https://uploads.example.test/" + request.objectKey());
        }

        @Override
        public StoredMediaObject inspect(String objectKey) {
            inspected.add(objectKey);
            StoredMediaObject object = stored.get(objectKey);
            if (object == null) {
                throw new MediaObjectNotFoundException(new IllegalStateException("missing fixture"));
            }
            return object;
        }

        @Override
        public void copy(MediaObjectCopy request) {
            copied.add(request);
            StoredMediaObject source = stored.get(request.sourceKey());
            if (source == null) {
                throw new MediaObjectNotFoundException(new IllegalStateException("missing fixture"));
            }
            stored.put(request.destinationKey(), source);
        }

        @Override
        public URI presignDownload(DownloadPresignRequest request) {
            return URI.create("https://downloads.example.test/" + request.objectKey()
                    + "?signature=redacted");
        }

        @Override
        public void delete(String objectKey) {
            deleted.add(objectKey);
            if (failDeletes) {
                throw new MediaObjectStorageException(new IllegalStateException("delete failed"));
            }
            stored.remove(objectKey);
        }

        void put(String objectKey, String contentType, byte[] bytes) {
            stored.put(objectKey, new StoredMediaObject(bytes.length, contentType, bytes));
        }

        List<String> inspectedKeys() {
            return List.copyOf(inspected);
        }

        List<MediaObjectCopy> copies() {
            return List.copyOf(copied);
        }

        List<String> deletedKeys() {
            return List.copyOf(deleted);
        }

        boolean contains(String objectKey) {
            return stored.containsKey(objectKey);
        }

        void reset() {
            stored.clear();
            inspected.clear();
            copied.clear();
            deleted.clear();
            failDeletes = false;
        }
    }
}
