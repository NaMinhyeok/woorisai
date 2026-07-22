package com.woorisai.diary.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.diary.DiaryEntryCommentCreated;
import com.woorisai.media.AttachScoreChangeMediaCommand;
import com.woorisai.media.AttachScoreCommentMediaCommand;
import com.woorisai.media.AttachedMedia;
import com.woorisai.media.AttachedMediaQuery;
import com.woorisai.media.AttachedMediaQuery.AttachedMediaUnavailableException;
import com.woorisai.media.DiaryEntryMediaParent;
import com.woorisai.media.MediaAttachmentMutation;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentConflictException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentForbiddenException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentUnavailableException;
import com.woorisai.media.MediaAttachmentMutation.MediaUploadNotFoundException;
import com.woorisai.media.MediaKind;
import com.woorisai.media.ReplaceDiaryEntryMediaCommand;
import com.woorisai.media.ScoreChangeMediaParent;
import com.woorisai.media.ScoreCommentMediaParent;
import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantReference;
import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.persistence.autoconfigure.EntityScan;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.event.ApplicationEvents;
import org.springframework.test.context.event.RecordApplicationEvents;

@SpringBootTest(
        classes = DiaryCleanSchemaH2Test.TestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@TestPropertySource(
        locations = "classpath:clean-schema-h2.properties",
        properties = {
            "spring.autoconfigure.exclude="
                + "org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration,"
                + "org.springframework.modulith.events.jpa.JpaEventPublicationAutoConfiguration,"
                + "org.springframework.modulith.events.config.EventPublicationAutoConfiguration",
            "spring.datasource.url=jdbc:h2:mem:diary-clean-schema;"
                + "MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;"
                + "DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE"
})
@RecordApplicationEvents
class DiaryCleanSchemaH2Test {

    private static final long FIRST = 3_000_000_001L;
    private static final long SECOND = 3_000_000_002L;
    private static final ParticipantReference FIRST_PARTICIPANT =
            new ParticipantReference(FIRST, 1, "Fixture One");
    private static final ParticipantReference SECOND_PARTICIPANT =
            new ParticipantReference(SECOND, 2, "Fixture Two");
    private static final UUID FIRST_UPLOAD =
            UUID.fromString("11111111-1111-4111-8111-111111111111");
    private static final UUID SECOND_UPLOAD =
            UUID.fromString("22222222-2222-4222-8222-222222222222");

    @Autowired
    private DiaryService diary;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private RecordingMedia media;

    @Autowired
    private ApplicationEvents applicationEvents;

    @BeforeEach
    void resetDatabase() {
        jdbc.update("DELETE FROM woorisai.media_attachment");
        jdbc.update("DELETE FROM woorisai.diary_entry_comment");
        jdbc.update("DELETE FROM woorisai.diary_entry");
        jdbc.update("DELETE FROM woorisai.participant");
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, 1, ?, CAST(? AS TIMESTAMP WITH TIME ZONE))
                """, FIRST, FIRST_PARTICIPANT.displayName(), "2026-07-21T00:00:00Z");
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, 2, ?, CAST(? AS TIMESTAMP WITH TIME ZONE))
                """, SECOND, SECOND_PARTICIPANT.displayName(), "2026-07-21T00:00:01Z");
        media.reset();
    }

    @Test
    void entryCrudPreservesPatchMeaningOwnershipAndDatabaseCascades() {
        DiaryEntryCreatedResponse created = diary.createEntry(
                FIRST,
                CreateDiaryEntryCommand.from(
                        "\t 함께 남길 기록 \u3000",
                        List.of(FIRST_UPLOAD, SECOND_UPLOAD)));

        assertThat(created.content()).isEqualTo("함께 남길 기록");
        assertThat(created.updatedAt()).isNull();
        assertThat(jdbc.queryForObject(
                "SELECT version FROM woorisai.diary_entry WHERE id = ?",
                Long.class,
                created.id())).isZero();
        assertThat(media.replacements()).containsExactly(new ReplaceDiaryEntryMediaCommand(
                FIRST, created.id(), List.of(FIRST_UPLOAD, SECOND_UPLOAD)));

        DiaryEntryUpdatedResponse contentOnly = diary.updateEntry(
                FIRST,
                created.id(),
                UpdateDiaryEntryCommand.from(" 수정한 기록 ", null));
        assertThat(contentOnly.content()).isEqualTo("수정한 기록");
        assertThat(contentOnly.updatedAt()).isNotNull();
        assertThat(jdbc.queryForObject(
                "SELECT version FROM woorisai.diary_entry WHERE id = ?",
                Long.class,
                created.id())).isOne();
        assertThat(media.replacements()).hasSize(1);

        DiaryEntryUpdatedResponse cleared = diary.updateEntry(
                FIRST,
                created.id(),
                UpdateDiaryEntryCommand.from(null, List.of()));
        assertThat(cleared.content()).isEqualTo("수정한 기록");
        assertThat(jdbc.queryForObject(
                "SELECT version FROM woorisai.diary_entry WHERE id = ?",
                Long.class,
                created.id())).isEqualTo(2L);
        assertThat(media.replacements().getLast().mediaUploadIds()).isEmpty();

        assertThatThrownBy(() -> diary.updateEntry(
                        SECOND,
                        created.id(),
                        UpdateDiaryEntryCommand.from("남의 글", null)))
                .isInstanceOf(DiaryMutationForbiddenException.class);
        assertThatThrownBy(() -> diary.deleteEntry(SECOND, created.id()))
                .isInstanceOf(DiaryMutationForbiddenException.class);

        DiaryEntryCommentCreatedResponse comment = diary.createComment(
                SECOND,
                created.id(),
                CreateDiaryCommentCommand.from("댓글"));
        assertThat(jdbc.queryForObject(
                "SELECT version FROM woorisai.diary_entry_comment WHERE id = ?",
                Long.class,
                comment.id())).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT version FROM woorisai.diary_entry WHERE id = ?",
                Long.class,
                created.id())).isEqualTo(2L);
        insertAttachedMedia(created.id(), FIRST_UPLOAD);
        int replacementCount = media.replacements().size();

        diary.deleteEntry(FIRST, created.id());

        assertThat(count("diary_entry", "id", created.id())).isZero();
        assertThat(count("diary_entry_comment", "id", comment.id())).isZero();
        assertThat(countUuid("media_attachment", "id", FIRST_UPLOAD)).isZero();
        assertThat(media.replacements()).hasSize(replacementCount);
    }

    @Test
    void mediaFailureRollsBackEntryCreationAndUpdate() {
        media.failNext(new MediaUploadNotFoundException());

        assertThatThrownBy(() -> diary.createEntry(
                        FIRST,
                        CreateDiaryEntryCommand.from("rollback", List.of(FIRST_UPLOAD))))
                .isInstanceOf(InvalidDiaryRequestException.class);
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.diary_entry", Long.class)).isZero();

        media.failNext(new MediaAttachmentForbiddenException());
        assertThatThrownBy(() -> diary.createEntry(
                        FIRST,
                        CreateDiaryEntryCommand.from("rollback", List.of(FIRST_UPLOAD))))
                .isInstanceOf(InvalidDiaryRequestException.class);
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.diary_entry", Long.class)).isZero();

        media.failNext(new MediaAttachmentConflictException());
        assertThatThrownBy(() -> diary.createEntry(
                        FIRST,
                        CreateDiaryEntryCommand.from("rollback", List.of(FIRST_UPLOAD))))
                .isInstanceOf(InvalidDiaryRequestException.class);
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.diary_entry", Long.class)).isZero();

        media.failNext(new MediaAttachmentUnavailableException());
        assertThatThrownBy(() -> diary.createEntry(
                        FIRST,
                        CreateDiaryEntryCommand.from("rollback", List.of(FIRST_UPLOAD))))
                .isInstanceOf(DiaryUnavailableException.class);
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.diary_entry", Long.class)).isZero();

        DiaryEntryCreatedResponse created = diary.createEntry(
                FIRST, CreateDiaryEntryCommand.from("original", List.of()));
        media.failNext(new MediaAttachmentUnavailableException());

        assertThatThrownBy(() -> diary.updateEntry(
                        FIRST,
                        created.id(),
                        UpdateDiaryEntryCommand.from("changed", List.of(FIRST_UPLOAD))))
                .isInstanceOf(DiaryUnavailableException.class);
        assertThat(jdbc.queryForObject(
                "SELECT content FROM woorisai.diary_entry WHERE id = ?",
                String.class,
                created.id())).isEqualTo("original");
        assertThat(jdbc.queryForObject(
                "SELECT version FROM woorisai.diary_entry WHERE id = ?",
                Long.class,
                created.id())).isZero();

        media.failNextQuery(new AttachedMediaUnavailableException(
                new IllegalStateException("fixture media query failure")));
        assertThatThrownBy(() -> diary.getEntry(FIRST, created.id()))
                .isInstanceOf(DiaryUnavailableException.class);
        assertThat(jdbc.queryForObject(
                "SELECT updated_at FROM woorisai.diary_entry WHERE id = ?",
                Instant.class,
                created.id())).isNull();
    }

    @Test
    void commentsAreFlatOrderedAuthorOwnedAndOnlyCreationPublishes() {
        long entryId = diary.createEntry(
                FIRST, CreateDiaryEntryCommand.from("entry", List.of())).id();
        DiaryEntryCommentCreatedResponse first = diary.createComment(
                SECOND, entryId, CreateDiaryCommentCommand.from(" first "));
        DiaryEntryCommentCreatedResponse second = diary.createComment(
                FIRST, entryId, CreateDiaryCommentCommand.from("second"));

        assertThat(applicationEvents.stream(DiaryEntryCommentCreated.class).toList())
                .containsExactly(
                        new DiaryEntryCommentCreated(FIRST, entryId),
                        new DiaryEntryCommentCreated(SECOND, entryId));
        assertThatThrownBy(() -> diary.updateComment(
                        FIRST, first.id(), UpdateDiaryCommentCommand.from("forbidden")))
                .isInstanceOf(DiaryMutationForbiddenException.class);

        DiaryEntryCommentUpdatedResponse updated = diary.updateComment(
                SECOND, first.id(), UpdateDiaryCommentCommand.from(" updated "));
        assertThat(updated.content()).isEqualTo("updated");
        assertThat(updated.updatedAt()).isNotNull();
        assertThat(jdbc.queryForObject(
                "SELECT version FROM woorisai.diary_entry_comment WHERE id = ?",
                Long.class,
                first.id())).isOne();
        assertThat(jdbc.queryForObject(
                "SELECT version FROM woorisai.diary_entry WHERE id = ?",
                Long.class,
                entryId)).isZero();

        DiaryEntryDetailResponse detail = diary.getEntry(FIRST, entryId);
        assertThat(detail.commentCount()).isEqualTo(2);
        assertThat(detail.comments())
                .extracting(DiaryCommentResponse::id)
                .containsExactly(first.id(), second.id());
        assertThat(detail.comments())
                .extracting(DiaryCommentResponse::isMine)
                .containsExactly(false, true);
        assertThat(applicationEvents.stream(DiaryEntryCommentCreated.class).count()).isEqualTo(2);

        assertThatThrownBy(() -> diary.deleteComment(FIRST, first.id()))
                .isInstanceOf(DiaryMutationForbiddenException.class);
        diary.deleteComment(SECOND, first.id());
        assertThat(applicationEvents.stream(DiaryEntryCommentCreated.class).count()).isEqualTo(2);
        assertThat(diary.getEntry(FIRST, entryId).commentCount()).isEqualTo(1);
    }

    @Test
    void listUsesOneBasedPagesNewestOrderCountsAndOrderedMedia() {
        for (long id = 10_001; id <= 10_021; id++) {
            jdbc.update("""
                    INSERT INTO woorisai.diary_entry
                        (id, author_id, content, created_at, updated_at)
                    VALUES (?, ?, ?, DATEADD('SECOND', ?,
                        CAST(? AS TIMESTAMP WITH TIME ZONE)), NULL)
                    """, id, FIRST, "entry-" + id, id - 10_000,
                    "2026-07-21T00:00:00Z");
        }
        jdbc.update("""
                INSERT INTO woorisai.diary_entry_comment
                    (id, diary_entry_id, author_id, content, created_at, updated_at)
                VALUES (20001, 10021, ?, 'comment',
                    CAST(? AS TIMESTAMP WITH TIME ZONE), NULL)
                """, SECOND, "2026-07-21T00:01:00Z");
        media.attachments().put(10_021L, List.of(new AttachedMedia(
                FIRST_UPLOAD,
                MediaKind.IMAGE,
                "memory.png",
                "image/png",
                512)));

        DiaryEntryListResponse firstPage = diary.listEntries(FIRST, 1);
        DiaryEntryListResponse secondPage = diary.listEntries(FIRST, 2);

        assertThat(firstPage.results()).hasSize(20);
        assertThat(firstPage.results().getFirst().id()).isEqualTo(10_021);
        assertThat(firstPage.results().getLast().id()).isEqualTo(10_002);
        assertThat(firstPage.results().getFirst().commentCount()).isEqualTo(1);
        assertThat(firstPage.results().getFirst().attachments())
                .extracting(DiaryMediaResponse::id)
                .containsExactly(FIRST_UPLOAD);
        assertThat(firstPage.pageNumber()).isEqualTo(1);
        assertThat(firstPage.pageSize()).isEqualTo(20);
        assertThat(firstPage.totalCount()).isEqualTo(21);
        assertThat(firstPage.hasNext()).isTrue();
        assertThat(secondPage.results())
                .extracting(DiaryEntryListItemResponse::id)
                .containsExactly(10_001L);
        assertThat(secondPage.hasNext()).isFalse();
    }

    @Test
    void listUsesIdDescendingWhenCreationTimesTie() {
        jdbc.update("""
                INSERT INTO woorisai.diary_entry
                    (id, author_id, content, created_at, updated_at)
                VALUES
                    (10001, ?, 'first', CAST(? AS TIMESTAMP WITH TIME ZONE), NULL),
                    (10002, ?, 'second', CAST(? AS TIMESTAMP WITH TIME ZONE), NULL)
                """,
                FIRST, "2026-07-21T00:00:00Z",
                SECOND, "2026-07-21T00:00:00Z");

        assertThat(diary.listEntries(FIRST, 1).results())
                .extracting(DiaryEntryListItemResponse::id)
                .containsExactly(10_002L, 10_001L);
    }

    @Test
    void rejectsEmptyPatchAndInvalidActorWithoutWriting() {
        long entryId = diary.createEntry(
                FIRST, CreateDiaryEntryCommand.from("entry", List.of())).id();

        assertThatThrownBy(() -> UpdateDiaryEntryCommand.from(null, null))
                .isInstanceOf(InvalidDiaryRequestException.class);
        assertThatThrownBy(() -> diary.listEntries(999, 1))
                .isInstanceOf(DiaryMutationForbiddenException.class);
        assertThat(jdbc.queryForObject(
                "SELECT content FROM woorisai.diary_entry WHERE id = ?",
                String.class,
                entryId)).isEqualTo("entry");
    }

    @Test
    void rejectsNullCodePointsBeforeEntryOrCommentPersistence() {
        assertThatThrownBy(() -> diary.createEntry(
                        FIRST,
                        CreateDiaryEntryCommand.from("before\u0000after", List.of())))
                .isInstanceOf(InvalidDiaryRequestException.class);
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.diary_entry", Long.class)).isZero();
        assertThat(media.replacements()).isEmpty();

        long entryId = diary.createEntry(
                FIRST, CreateDiaryEntryCommand.from("entry", List.of())).id();
        int replacementCount = media.replacements().size();

        assertThatThrownBy(() -> diary.createComment(
                        SECOND,
                        entryId,
                        CreateDiaryCommentCommand.from("before\u0000after")))
                .isInstanceOf(InvalidDiaryRequestException.class);
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.diary_entry_comment", Long.class)).isZero();
        assertThat(media.replacements()).hasSize(replacementCount);
        assertThat(applicationEvents.stream(DiaryEntryCommentCreated.class)).isEmpty();
    }

    private void insertAttachedMedia(long entryId, UUID id) {
        jdbc.update("""
                INSERT INTO woorisai.media_attachment (
                    id, uploader_id, score_change_id, score_change_comment_id,
                    diary_entry_id, purpose, kind, status, object_key,
                    original_name, content_type, expected_size, actual_size,
                    position, created_at, ready_at)
                VALUES (?, ?, NULL, NULL, ?, 'DIARY_ENTRY', 'IMAGE', 'READY', ?,
                    'memory.png', 'image/png', 512, 512, 0,
                    CAST(? AS TIMESTAMP WITH TIME ZONE),
                    CAST(? AS TIMESTAMP WITH TIME ZONE))
                """, id, FIRST, entryId, "media/" + id,
                "2026-07-21T00:00:00Z", "2026-07-21T00:00:01Z");
    }

    private long count(String table, String column, long id) {
        return jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai." + table + " WHERE " + column + " = ?",
                Long.class,
                id);
    }

    private long countUuid(String table, String column, UUID id) {
        return jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai." + table + " WHERE " + column + " = ?",
                Long.class,
                id);
    }

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackages = "com.woorisai.diary.internal")
    @EnableJpaRepositories(basePackages = "com.woorisai.diary.internal")
    @Import(DiaryService.class)
    static class TestApplication {

        @Bean
        Clock clock() {
            return Clock.systemUTC();
        }

        @Bean
        ParticipantDirectory participantDirectory() {
            return () -> new CanonicalParticipantPair(
                    FIRST_PARTICIPANT, SECOND_PARTICIPANT);
        }

        @Bean
        RecordingMedia recordingMedia() {
            return new RecordingMedia();
        }
    }

    static final class RecordingMedia implements MediaAttachmentMutation, AttachedMediaQuery {

        private final List<ReplaceDiaryEntryMediaCommand> replacements = new ArrayList<>();
        private final Map<Long, List<AttachedMedia>> attachments = new LinkedHashMap<>();
        private RuntimeException nextFailure;
        private RuntimeException nextQueryFailure;

        @Override
        public void attachScoreChange(AttachScoreChangeMediaCommand command) {
            throw new UnsupportedOperationException();
        }

        @Override
        public void attachScoreComment(AttachScoreCommentMediaCommand command) {
            throw new UnsupportedOperationException();
        }

        @Override
        public void replaceDiaryEntry(ReplaceDiaryEntryMediaCommand command) {
            replacements.add(command);
            if (nextFailure != null) {
                RuntimeException failure = nextFailure;
                nextFailure = null;
                throw failure;
            }
        }

        @Override
        public Map<Long, List<AttachedMedia>> attachmentsForScoreChanges(
                List<ScoreChangeMediaParent> scoreChanges) {
            throw new UnsupportedOperationException();
        }

        @Override
        public Map<Long, List<AttachedMedia>> attachmentsForScoreComments(
                List<ScoreCommentMediaParent> scoreComments) {
            throw new UnsupportedOperationException();
        }

        @Override
        public Map<Long, List<AttachedMedia>> attachmentsForDiaryEntries(
                List<DiaryEntryMediaParent> diaryEntries) {
            if (nextQueryFailure != null) {
                RuntimeException failure = nextQueryFailure;
                nextQueryFailure = null;
                throw failure;
            }
            Map<Long, List<AttachedMedia>> result = new LinkedHashMap<>();
            diaryEntries.forEach(parent -> result.put(
                    parent.diaryEntryId(),
                    List.copyOf(attachments.getOrDefault(parent.diaryEntryId(), List.of()))));
            return Map.copyOf(result);
        }

        List<ReplaceDiaryEntryMediaCommand> replacements() {
            return replacements;
        }

        Map<Long, List<AttachedMedia>> attachments() {
            return attachments;
        }

        void failNext(RuntimeException failure) {
            nextFailure = failure;
        }

        void failNextQuery(RuntimeException failure) {
            nextQueryFailure = failure;
        }

        void reset() {
            replacements.clear();
            attachments.clear();
            nextFailure = null;
            nextQueryFailure = null;
        }
    }
}
