package com.woorisai.relationship.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.media.AttachScoreChangeMediaCommand;
import com.woorisai.media.AttachScoreCommentMediaCommand;
import com.woorisai.media.AttachedMedia;
import com.woorisai.media.AttachedMediaQuery;
import com.woorisai.media.DiaryEntryMediaParent;
import com.woorisai.media.MediaAttachmentMutation;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentConflictException;
import com.woorisai.media.MediaKind;
import com.woorisai.media.ReplaceDiaryEntryMediaCommand;
import com.woorisai.media.ScoreChangeMediaParent;
import com.woorisai.media.ScoreCommentMediaParent;
import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantReference;
import com.woorisai.relationship.RelationshipScoreChanged;
import com.woorisai.relationship.ScoreChangeCommentCreated;
import java.time.Clock;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.persistence.autoconfigure.EntityScan;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.event.EventListener;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;

@SpringBootTest(
        classes = RelationshipServiceCleanSchemaTest.TestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@TestPropertySource(
        locations = "classpath:clean-schema-h2.properties",
        properties = {
            "spring.autoconfigure.exclude="
                + "org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration,"
                + "org.springframework.modulith.events.jpa.JpaEventPublicationAutoConfiguration,"
                + "org.springframework.modulith.events.config.EventPublicationAutoConfiguration",
            "spring.datasource.url=jdbc:h2:mem:relationship-clean-schema;"
                + "MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;"
                + "DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE"
})
class RelationshipServiceCleanSchemaTest {

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
    private FakeMedia media;

    @Autowired
    private RecordedEvents events;

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
                    (10, ?, ?, 50, ?),
                    (11, ?, ?, 70, ?)
                """, FIRST, SECOND, NOW, SECOND, FIRST, NOW);
        media.reset();
        events.reset();
    }

    @Test
    void readsAndWritesTheTwoUserRelationshipWithMediaAndPrivacySafeEvents() {
        RelationshipScoresResponse scores = relationships.relationshipScores(FIRST);
        assertThat(scores.self()).isEqualTo(new ParticipantView(1, "Fixture One", true));
        assertThat(scores.partner()).isEqualTo(new ParticipantView(2, "Fixture Two", false));
        assertThat(scores.outgoing().currentScore()).isEqualTo(50);
        assertThat(scores.incoming().currentScore()).isEqualTo(70);

        UUID scoreImage = UUID.fromString("61000000-0000-4000-8000-000000000001");
        ScoreChangeCreatedResponse changed = relationships.changeScore(
                FIRST,
                ChangeScoreCommand.from(1, null, "  because  ", List.of(scoreImage)));

        assertThat(changed.change().delta()).isEqualTo(1);
        assertThat(changed.change().reason()).isEqualTo("because");
        assertThat(changed.change().attachments()).hasSize(1);
        assertThat(changed.outgoing().currentScore()).isEqualTo(51);
        assertThat(changed.change().createdAt().getNano() % 1_000).isZero();
        assertThat(changed.outgoing().updatedAt()).isEqualTo(changed.change().createdAt());
        assertThat(changed.change().createdAt()).isEqualTo(storedInstant(
                "SELECT created_at FROM woorisai.score_change WHERE id = ?",
                changed.change().id()));
        assertThat(changed.outgoing().updatedAt()).isEqualTo(storedInstant(
                "SELECT updated_at FROM woorisai.relationship_score WHERE id = ?",
                10));
        assertThat(jdbc.queryForObject(
                "SELECT current_score FROM woorisai.relationship_score WHERE id = 10",
                Integer.class)).isEqualTo(51);
        assertThat(jdbc.queryForObject(
                "SELECT version FROM woorisai.relationship_score WHERE id = 10",
                Long.class)).isOne();
        assertThat(media.scoreCommands).containsExactly(new AttachScoreChangeMediaCommand(
                FIRST, changed.change().id(), List.of(scoreImage)));
        assertThat(events.values).containsExactly(new RelationshipScoreChanged(
                SECOND, changed.change().id()));

        UUID commentImage = UUID.fromString("62000000-0000-4000-8000-000000000001");
        ScoreChangeCommentCreatedResponse commented = relationships.createComment(
                SECOND,
                changed.change().id(),
                CreateScoreCommentCommand.from(" \t ", List.of(commentImage)));

        assertThat(commented.comment().content()).isNull();
        assertThat(commented.comment().author()).isEqualTo(
                new ParticipantView(2, "Fixture Two", true));
        assertThat(commented.comment().attachments()).hasSize(1);
        assertThat(commented.comment().createdAt().getNano() % 1_000).isZero();
        assertThat(commented.comment().createdAt()).isEqualTo(storedInstant(
                "SELECT created_at FROM woorisai.score_change_comment WHERE id = ?",
                commented.comment().id()));
        assertThat(jdbc.queryForObject("""
                SELECT content IS NULL
                FROM woorisai.score_change_comment
                WHERE id = ?
                """, Boolean.class, commented.comment().id())).isTrue();
        assertThat(media.commentCommands).containsExactly(new AttachScoreCommentMediaCommand(
                SECOND, commented.comment().id(), List.of(commentImage)));
        assertThat(events.values).containsExactly(
                new RelationshipScoreChanged(SECOND, changed.change().id()),
                new ScoreChangeCommentCreated(FIRST, changed.change().id()));

        ScoreChangeThreadResponse thread = relationships.scoreChange(
                FIRST, changed.change().id());
        assertThat(thread.change().commentCount()).isOne();
        assertThat(thread.comments()).hasSize(1);
        assertThat(thread.comments().getFirst().author().mine()).isFalse();
        assertThat(thread.comments().getFirst().attachments()).hasSize(1);

        ScoreChangeHistoryResponse history = relationships.scoreChanges(FIRST, 1);
        assertThat(history.results()).hasSize(1);
        assertThat(history.results().getFirst().commentCount()).isOne();
        assertThat(history.paging()).isEqualTo(
                new ScoreChangeHistoryResponse.Paging(1, 20, false, 1));
    }

    @Test
    void appliesAnAbsoluteTargetOnlyToTheActorsOutgoingDirection() {
        ScoreChangeCreatedResponse changed = relationships.changeScore(
                SECOND,
                ChangeScoreCommand.from(null, 80, null, List.of()));

        assertThat(changed.change().sourceParticipant().slot()).isEqualTo(2);
        assertThat(changed.change().targetParticipant().slot()).isEqualTo(1);
        assertThat(changed.change().changedBy().slot()).isEqualTo(2);
        assertThat(changed.change().delta()).isEqualTo(10);
        assertThat(changed.change().resultingScore()).isEqualTo(80);
        assertThat(changed.outgoing().currentScore()).isEqualTo(80);
        assertThat(jdbc.queryForObject(
                "SELECT current_score FROM woorisai.relationship_score WHERE id = 10",
                Integer.class)).isEqualTo(50);
        assertThat(jdbc.queryForObject(
                "SELECT version FROM woorisai.relationship_score WHERE id = 10",
                Long.class)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT current_score FROM woorisai.relationship_score WHERE id = 11",
                Integer.class)).isEqualTo(80);
        assertThat(jdbc.queryForObject(
                "SELECT version FROM woorisai.relationship_score WHERE id = 11",
                Long.class)).isOne();
        assertThat(jdbc.queryForObject(
                "SELECT relationship_score_id FROM woorisai.score_change",
                Long.class)).isEqualTo(11L);
        assertThat(jdbc.queryForObject(
                "SELECT changed_by_id FROM woorisai.score_change",
                Long.class)).isEqualTo(SECOND);
        assertThat(jdbc.queryForObject(
                "SELECT delta FROM woorisai.score_change",
                Integer.class)).isEqualTo(10);
        assertThat(jdbc.queryForObject(
                "SELECT resulting_score FROM woorisai.score_change",
                Integer.class)).isEqualTo(80);
        assertThat(events.values).containsExactly(new RelationshipScoreChanged(
                FIRST, changed.change().id()));
    }

    @Test
    void rollsBackTheScoreAndImmutableHistoryWhenMediaAttachmentFails() {
        media.failScoreAttach = true;

        assertThatThrownBy(() -> relationships.changeScore(
                        FIRST,
                        ChangeScoreCommand.from(1, null, null, List.of())))
                .isInstanceOf(RelationshipConflictException.class);

        assertThat(jdbc.queryForObject(
                "SELECT current_score FROM woorisai.relationship_score WHERE id = 10",
                Integer.class)).isEqualTo(50);
        assertThat(jdbc.queryForObject(
                "SELECT version FROM woorisai.relationship_score WHERE id = 10",
                Long.class)).isZero();
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.score_change",
                Integer.class)).isZero();
        assertThat(events.values).isEmpty();
    }

    @Test
    void rejectsStateConflictsAndNonParticipants() {
        assertThatThrownBy(() -> relationships.changeScore(
                        FIRST,
                        ChangeScoreCommand.from(null, 50, null, List.of())))
                .isInstanceOf(RelationshipConflictException.class);
        assertThatThrownBy(() -> relationships.relationshipScores(9_999))
                .isInstanceOf(RelationshipForbiddenException.class);
    }

    @Test
    void failsClosedWhenTheDirectionalScorePairIsIncomplete() {
        jdbc.update("DELETE FROM woorisai.relationship_score WHERE id = 11");

        assertThatThrownBy(() -> relationships.relationshipScores(FIRST))
                .isInstanceOf(RelationshipUnavailableException.class);
    }

    @Test
    void rejectsValidCommandsThatConflictWithCurrentState() {
        assertThatThrownBy(() -> relationships.changeScore(
                        FIRST,
                        ChangeScoreCommand.from(51, null, null, List.of())))
                .isInstanceOf(RelationshipConflictException.class);

        assertThat(jdbc.queryForObject(
                "SELECT current_score FROM woorisai.relationship_score WHERE id = 10",
                Integer.class)).isEqualTo(50);
        assertThat(jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.score_change",
                Integer.class)).isZero();
        assertThat(events.values).isEmpty();
    }

    @Test
    void returnsAnEmptyFirstHistoryPageButRejectsAnEmptyLaterPage() {
        ScoreChangeHistoryResponse firstPage = relationships.scoreChanges(FIRST, 1);

        assertThat(firstPage.results()).isEmpty();
        assertThat(firstPage.paging()).isEqualTo(
                new ScoreChangeHistoryResponse.Paging(1, 20, false, 0));
        assertThatThrownBy(() -> relationships.scoreChanges(FIRST, 2))
                .isInstanceOf(RelationshipNotFoundException.class);
    }

    @Test
    void historyOrdersByCreationTimeThenIdDescending() {
        jdbc.update("""
                INSERT INTO woorisai.score_change (
                    id, relationship_score_id, changed_by_id, delta,
                    resulting_score, reason, created_at
                ) VALUES
                    (20, 10, ?, 1, 51, NULL, ?),
                    (21, 10, ?, 1, 52, NULL, ?),
                    (22, 11, ?, -1, 69, NULL, ?)
                """,
                FIRST, NOW,
                FIRST, NOW,
                SECOND, NOW.plusSeconds(1));

        assertThat(relationships.scoreChanges(FIRST, 1).results())
                .extracting(ScoreChangeView::id)
                .containsExactly(22L, 21L, 20L);
    }

    private Instant storedInstant(String sql, long id) {
        return jdbc.queryForObject(sql, OffsetDateTime.class, id).toInstant();
    }

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackageClasses = RelationshipScore.class)
    @EnableJpaRepositories(basePackageClasses = RelationshipScoreRepository.class)
    @Import({RelationshipService.class, TestBeans.class})
    static class TestApplication {}

    @TestConfiguration(proxyBeanMethods = false)
    static class TestBeans {

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
        FakeMedia fakeMedia() {
            return new FakeMedia();
        }

        @Bean
        RecordedEvents recordedEvents() {
            return new RecordedEvents();
        }
    }

    static final class FakeMedia implements MediaAttachmentMutation, AttachedMediaQuery {

        private final List<AttachScoreChangeMediaCommand> scoreCommands = new ArrayList<>();
        private final List<AttachScoreCommentMediaCommand> commentCommands = new ArrayList<>();
        private final Map<Long, List<AttachedMedia>> scoreAttachments = new LinkedHashMap<>();
        private final Map<Long, List<AttachedMedia>> commentAttachments = new LinkedHashMap<>();
        private boolean failScoreAttach;

        @Override
        public void attachScoreChange(AttachScoreChangeMediaCommand command) {
            if (failScoreAttach) {
                throw new MediaAttachmentConflictException();
            }
            scoreCommands.add(command);
            scoreAttachments.put(
                    command.scoreChangeId(),
                    command.mediaUploadIds().stream().map(FakeMedia::attached).toList());
        }

        @Override
        public void attachScoreComment(AttachScoreCommentMediaCommand command) {
            commentCommands.add(command);
            commentAttachments.put(
                    command.scoreCommentId(),
                    command.mediaUploadIds().stream().map(FakeMedia::attached).toList());
        }

        @Override
        public void replaceDiaryEntry(ReplaceDiaryEntryMediaCommand command) {
            throw new UnsupportedOperationException();
        }

        @Override
        public Map<Long, List<AttachedMedia>> attachmentsForScoreChanges(
                List<ScoreChangeMediaParent> parents) {
            Map<Long, List<AttachedMedia>> result = new LinkedHashMap<>();
            parents.forEach(parent -> result.put(
                    parent.scoreChangeId(),
                    scoreAttachments.getOrDefault(parent.scoreChangeId(), List.of())));
            return Map.copyOf(result);
        }

        @Override
        public Map<Long, List<AttachedMedia>> attachmentsForScoreComments(
                List<ScoreCommentMediaParent> parents) {
            Map<Long, List<AttachedMedia>> result = new LinkedHashMap<>();
            parents.forEach(parent -> result.put(
                    parent.scoreCommentId(),
                    commentAttachments.getOrDefault(parent.scoreCommentId(), List.of())));
            return Map.copyOf(result);
        }

        @Override
        public Map<Long, List<AttachedMedia>> attachmentsForDiaryEntries(
                List<DiaryEntryMediaParent> parents) {
            throw new UnsupportedOperationException();
        }

        void reset() {
            scoreCommands.clear();
            commentCommands.clear();
            scoreAttachments.clear();
            commentAttachments.clear();
            failScoreAttach = false;
        }

        private static AttachedMedia attached(UUID id) {
            return new AttachedMedia(id, MediaKind.IMAGE, id + ".png", "image/png", 8);
        }
    }

    static final class RecordedEvents {

        private final List<Object> values = new CopyOnWriteArrayList<>();

        @EventListener
        void scoreChanged(RelationshipScoreChanged event) {
            values.add(event);
        }

        @EventListener
        void commentCreated(ScoreChangeCommentCreated event) {
            values.add(event);
        }

        void reset() {
            values.clear();
        }
    }
}
