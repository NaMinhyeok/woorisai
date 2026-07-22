package com.woorisai.testing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.testcontainers.postgresql.PostgreSQLContainer;

@Tag("postgres")
class CleanSchemaPostgresMigrationTest {

    private static final PostgreSQLContainer POSTGRES = WoorisaiPostgresContainer.create();

    @BeforeAll
    static void migrateEmptyDatabase() throws SQLException {
        POSTGRES.start();

        try (Connection connection = connection()) {
            execute(connection, """
                    CREATE TABLE public.django_schema_sentinel
                    (
                        id     SMALLINT PRIMARY KEY,
                        marker TEXT NOT NULL
                    )
                    """);
            execute(connection, """
                    INSERT INTO public.django_schema_sentinel (id, marker)
                    VALUES (1, 'preserve-django-public')
                    """);
        }

        var v1Result = flywayAt(MigrationVersion.fromVersion("1")).migrate();
        assertThat(v1Result.migrationsExecuted).isOne();

        try (Connection connection = connection()) {
            execute(connection, """
                    INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                    VALUES
                        (9001, 1, 'upgrade-fixture-one', TIMESTAMPTZ '2026-07-21 00:00:00Z'),
                        (9002, 2, 'upgrade-fixture-two', TIMESTAMPTZ '2026-07-21 00:00:01Z')
                    """);
            execute(connection, """
                    INSERT INTO woorisai.relationship_score (
                        id, source_participant_id, target_participant_id, current_score, updated_at
                    ) VALUES (
                        9010, 9001, 9002, 50, TIMESTAMPTZ '2026-07-21 00:00:02Z'
                    )
                    """);
            execute(connection, """
                    INSERT INTO woorisai.diary_entry (id, author_id, content, created_at)
                    VALUES (
                        9040, 9001, 'upgrade fixture', TIMESTAMPTZ '2026-07-21 00:00:03Z'
                    )
                    """);
            execute(connection, """
                    INSERT INTO woorisai.diary_entry_comment (
                        id, diary_entry_id, author_id, content, created_at
                    ) VALUES (
                        9050, 9040, 9002, 'upgrade comment',
                        TIMESTAMPTZ '2026-07-21 00:00:04Z'
                    )
                    """);
        }

        var v2Result = flyway().migrate();
        assertThat(v2Result.migrationsExecuted).isOne();

        try (Connection connection = connection()) {
            assertThat(queryInt(connection, """
                    SELECT COUNT(*)
                    FROM (
                        SELECT id
                        FROM woorisai.relationship_score
                        WHERE id = 9010 AND version = 0
                        UNION ALL
                        SELECT id
                        FROM woorisai.diary_entry
                        WHERE id = 9040 AND version = 0
                        UNION ALL
                        SELECT id
                        FROM woorisai.diary_entry_comment
                        WHERE id = 9050 AND version = 0
                    ) preserved_v1_rows
                    """))
                    .isEqualTo(3);
            execute(connection, "DELETE FROM woorisai.diary_entry WHERE id = 9040");
            execute(connection, "DELETE FROM woorisai.relationship_score WHERE id = 9010");
            execute(connection, "DELETE FROM woorisai.participant WHERE id IN (9001, 9002)");
        }
    }

    @AfterAll
    static void stopDatabase() {
        POSTGRES.stop();
    }

    @Test
    void createsTheIsolatedSchemaWithByDefaultIdentitiesAndModulithRegistry() throws Exception {
        try (Connection connection = connection()) {
            assertThat(queryStrings(connection, """
                    SELECT table_name
                    FROM information_schema.tables
                    WHERE table_schema = 'woorisai'
                    ORDER BY table_name
                    """))
                    .containsExactly(
                            "diary_entry",
                            "diary_entry_comment",
                            "event_publication",
                            "flyway_schema_history",
                            "media_attachment",
                            "notification_fid",
                            "participant",
                            "participant_credential",
                            "relationship_score",
                            "score_change",
                            "score_change_comment"
                    );

            assertThat(queryStrings(connection, """
                    SELECT table_name || ':' || udt_name || ':' || is_nullable
                    FROM information_schema.columns
                    WHERE table_schema = 'woorisai'
                      AND table_name IN (
                          'relationship_score', 'diary_entry', 'diary_entry_comment'
                      )
                      AND column_name = 'version'
                    ORDER BY table_name
                    """))
                    .containsExactly(
                            "diary_entry:int8:NO",
                            "diary_entry_comment:int8:NO",
                            "relationship_score:int8:NO"
                    );
            assertThat(queryInt(connection, """
                    SELECT COUNT(*)
                    FROM information_schema.columns
                    WHERE table_schema = 'woorisai'
                      AND table_name IN (
                          'relationship_score', 'diary_entry', 'diary_entry_comment'
                      )
                      AND column_name = 'version'
                      AND column_default IS NOT NULL
                    """))
                    .isEqualTo(3);

            assertThat(queryStrings(connection, """
                    SELECT table_schema
                    FROM information_schema.tables
                    WHERE table_name = 'flyway_schema_history'
                    ORDER BY table_schema
                    """))
                    .containsExactly("woorisai");
            assertThat(queryStrings(connection, """
                    SELECT marker
                    FROM public.django_schema_sentinel
                    WHERE id = 1
                    """))
                    .containsExactly("preserve-django-public");

            assertThat(queryStrings(connection, """
                    SELECT table_name
                    FROM information_schema.columns
                    WHERE table_schema = 'woorisai'
                      AND is_identity = 'YES'
                      AND identity_generation = 'BY DEFAULT'
                    ORDER BY table_name
                    """))
                    .containsExactly(
                            "diary_entry",
                            "diary_entry_comment",
                            "notification_fid",
                            "participant",
                            "relationship_score",
                            "score_change",
                            "score_change_comment"
                    );

            assertThat(queryStrings(connection, """
                    SELECT column_name || ':' || udt_name || ':' || is_nullable
                    FROM information_schema.columns
                    WHERE table_schema = 'woorisai'
                      AND table_name = 'event_publication'
                    ORDER BY ordinal_position
                    """))
                    .containsExactly(
                            "id:uuid:NO",
                            "listener_id:text:NO",
                            "event_type:text:NO",
                            "serialized_event:text:NO",
                            "publication_date:timestamptz:NO",
                            "completion_date:timestamptz:YES",
                            "status:text:YES",
                            "completion_attempts:int4:YES",
                            "last_resubmission_date:timestamptz:YES"
                    );

            assertThat(queryStrings(connection, """
                    SELECT indexname || ':' || indexdef
                    FROM pg_indexes
                    WHERE schemaname = 'woorisai'
                      AND tablename = 'event_publication'
                      AND indexname IN (
                          'event_publication_serialized_event_hash_idx',
                          'event_publication_by_completion_date_idx'
                      )
                    ORDER BY indexname
                    """))
                    .containsExactly(
                            "event_publication_by_completion_date_idx:"
                                    + "CREATE INDEX event_publication_by_completion_date_idx "
                                    + "ON woorisai.event_publication USING btree (completion_date)",
                            "event_publication_serialized_event_hash_idx:"
                                    + "CREATE INDEX event_publication_serialized_event_hash_idx "
                                    + "ON woorisai.event_publication USING hash (serialized_event)"
                    );

            assertThat(queryInt(connection, """
                    SELECT COUNT(*)
                    FROM information_schema.tables
                    WHERE table_schema IN ('public', 'woorisai')
                      AND table_name IN ('app_access_token', 'access_token')
                    """))
                    .isZero();
        }

        assertThat(flyway().migrate().migrationsExecuted).isZero();
    }

    @Test
    void enforcesTopologyAndRequiresLegacyEmptyReasonAndMediaOnlyCommentTextToBeCopiedAsNull()
            throws Exception {
        try (Connection connection = connection()) {
            insertCanonicalParticipants(connection);

            assertConstraintViolation(connection, "23514", "participant_slot_ck", """
                    INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                    VALUES (3, 3, 'invalid-slot', TIMESTAMPTZ '2026-07-21 00:00:00Z')
                    """);

            execute(connection, """
                    INSERT INTO woorisai.participant_credential (participant_id, pin_hash, updated_at)
                    VALUES (1, 'synthetic-password-encoder-output', TIMESTAMPTZ '2026-07-21 00:00:00Z')
                    """);
            assertConstraintViolation(
                    connection,
                    "23503",
                    "participant_credential_participant_fk",
                    """
                    INSERT INTO woorisai.participant_credential (participant_id, pin_hash, updated_at)
                    VALUES (999, 'synthetic-password-encoder-output', TIMESTAMPTZ '2026-07-21 00:00:00Z')
                    """
            );

            execute(connection, """
                    INSERT INTO woorisai.relationship_score (
                        id, source_participant_id, target_participant_id, current_score, updated_at
                    ) VALUES (
                        10, 1, 2, 50, TIMESTAMPTZ '2026-07-21 00:00:00Z'
                    )
                    """);
            assertConstraintViolation(connection, "23514", "relationship_score_value_ck", """
                    INSERT INTO woorisai.relationship_score (
                        id, source_participant_id, target_participant_id, current_score, updated_at
                    ) VALUES (
                        11, 2, 1, 101, TIMESTAMPTZ '2026-07-21 00:00:00Z'
                    )
                    """);
            assertConstraintViolation(connection, "23503", "score_change_outgoing_owner_fk", """
                    INSERT INTO woorisai.score_change (
                        id, relationship_score_id, changed_by_id, delta,
                        resulting_score, reason, created_at
                    ) VALUES (
                        19, 10, 2, 5, 55, NULL, TIMESTAMPTZ '2026-07-21 00:01:00Z'
                    )
                    """);
            assertConstraintViolation(connection, "23514", "score_change_delta_ck", """
                    INSERT INTO woorisai.score_change (
                        id, relationship_score_id, changed_by_id, delta,
                        resulting_score, reason, created_at
                    ) VALUES (
                        19, 10, 1, 101, 55, NULL, TIMESTAMPTZ '2026-07-21 00:01:00Z'
                    )
                    """);

            execute(connection, """
                    INSERT INTO woorisai.score_change (
                        id, relationship_score_id, changed_by_id, delta,
                        resulting_score, reason, created_at
                    ) VALUES (
                        20, 10, 1, 5, 55, NULL, TIMESTAMPTZ '2026-07-21 00:01:00Z'
                    )
                    """);
            assertThat(queryInt(connection, """
                    SELECT COUNT(*)
                    FROM woorisai.score_change
                    WHERE id = 20 AND reason IS NULL
                    """))
                    .isOne();
            assertConstraintViolation(connection, "23514", "score_change_reason_ck", """
                    INSERT INTO woorisai.score_change (
                        id, relationship_score_id, changed_by_id, delta,
                        resulting_score, reason, created_at
                    ) VALUES (
                        21, 10, 1, 5, 55, '', TIMESTAMPTZ '2026-07-21 00:01:00Z'
                    )
                    """);
            execute(connection, """
                    INSERT INTO woorisai.score_change_comment (
                        id, score_change_id, author_id, content, created_at
                    ) VALUES (
                        30, 20, 2, NULL, TIMESTAMPTZ '2026-07-21 00:02:00Z'
                    )
                    """);
            assertThat(queryInt(connection, """
                    SELECT COUNT(*)
                    FROM woorisai.score_change_comment
                    WHERE id = 30 AND content IS NULL
                    """))
                    .isOne();
            assertConstraintViolation(
                    connection,
                    "23514",
                    "score_change_comment_content_ck",
                    """
                            INSERT INTO woorisai.score_change_comment (
                                id, score_change_id, author_id, content, created_at
                            ) VALUES (
                                31, 20, 2, '', TIMESTAMPTZ '2026-07-21 00:02:00Z'
                            )
                            """
            );

            assertConstraintViolation(connection, "23514", "media_attachment_object_key_ck", """
                    INSERT INTO woorisai.media_attachment (
                        id, uploader_id, purpose, kind, status, object_key, original_name,
                        content_type, expected_size, position, created_at
                    ) VALUES (
                        '40000000-0000-4000-8000-000000000009', 1,
                        'DIARY_ENTRY', 'IMAGE', 'PENDING', '   ', 'blank.png',
                        'image/png', 1024, 0,
                        TIMESTAMPTZ '2026-07-21 00:00:00Z'
                    )
                    """);

            UUID mediaId = UUID.fromString("40000000-0000-4000-8000-000000000001");
            assertConstraintViolation(connection, "23514", "media_attachment_state_ck", """
                    INSERT INTO woorisai.media_attachment (
                        id, uploader_id, purpose, kind, status, object_key, original_name,
                        content_type, expected_size, position, created_at
                    ) VALUES (
                        '40000000-0000-4000-8000-000000000002', 2,
                        'SCORE_CHANGE_COMMENT', 'IMAGE', 'PENDING',
                        'pending/invalid-position', 'image.png', 'image/png', 1024, 1,
                        TIMESTAMPTZ '2026-07-21 00:03:00Z'
                    )
                    """);
            execute(connection, """
                    INSERT INTO woorisai.media_attachment (
                        id, uploader_id, purpose, kind, status, object_key, original_name,
                        content_type, expected_size, position, created_at
                    ) VALUES (
                        '%s', 2, 'SCORE_CHANGE_COMMENT', 'IMAGE', 'PENDING',
                        'pending/postgres-image', 'image.png', 'image/png', 1024, 0,
                        TIMESTAMPTZ '2026-07-21 00:03:00Z'
                    )
                    """.formatted(mediaId));

            assertConstraintViolation(connection, "23514", "media_attachment_state_ck", """
                    UPDATE woorisai.media_attachment
                    SET status = 'READY', actual_size = 1023,
                        ready_at = TIMESTAMPTZ '2026-07-21 00:04:00Z'
                    WHERE id = '%s'
                    """.formatted(mediaId));

            execute(connection, """
                    UPDATE woorisai.media_attachment
                    SET status = 'READY', actual_size = 1024,
                        ready_at = TIMESTAMPTZ '2026-07-21 00:04:00Z',
                        score_change_comment_id = 30
                    WHERE id = '%s'
                    """.formatted(mediaId));

            assertConstraintViolation(
                    connection,
                    "23503",
                    "media_attachment_diary_entry_fk",
                    """
                            INSERT INTO woorisai.media_attachment (
                                id, uploader_id, diary_entry_id, purpose, kind, status, object_key,
                                original_name, content_type, expected_size, actual_size, position,
                                created_at, ready_at
                            ) VALUES (
                                '40000000-0000-4000-8000-000000000006', 1, 999,
                                'DIARY_ENTRY', 'IMAGE', 'READY', 'ready/missing-diary-image',
                                'missing-diary.png', 'image/png', 1024, 1024, 0,
                                TIMESTAMPTZ '2026-07-21 00:05:00Z',
                                TIMESTAMPTZ '2026-07-21 00:06:00Z'
                            )
                            """
            );

            execute(connection, """
                    INSERT INTO woorisai.media_attachment (
                        id, uploader_id, score_change_id, purpose, kind, status, object_key,
                        original_name, content_type, expected_size, actual_size, position,
                        created_at, ready_at
                    ) VALUES (
                        '40000000-0000-4000-8000-000000000004', 1, 20,
                        'SCORE_CHANGE', 'IMAGE', 'READY', 'ready/score-image',
                        'score.png', 'image/png', 1024, 1024, 0,
                        TIMESTAMPTZ '2026-07-21 00:05:00Z',
                        TIMESTAMPTZ '2026-07-21 00:06:00Z'
                    )
                    """);
            assertConstraintViolation(connection, "23505", "media_attachment_score_uq", """
                    INSERT INTO woorisai.media_attachment (
                        id, uploader_id, score_change_id, purpose, kind, status, object_key,
                        original_name, content_type, expected_size, actual_size, position,
                        created_at, ready_at
                    ) VALUES (
                        '40000000-0000-4000-8000-000000000005', 1, 20,
                        'SCORE_CHANGE', 'IMAGE', 'READY', 'ready/duplicate-score-image',
                        'duplicate.png', 'image/png', 1024, 1024, 0,
                        TIMESTAMPTZ '2026-07-21 00:05:00Z',
                        TIMESTAMPTZ '2026-07-21 00:06:00Z'
                    )
                    """);

            execute(connection, """
                    INSERT INTO woorisai.diary_entry (
                        id, author_id, content, created_at
                    ) VALUES (
                        40, 1, 'synthetic diary', TIMESTAMPTZ '2026-07-21 00:05:00Z'
                    )
                    """);
            execute(connection, """
                    INSERT INTO woorisai.media_attachment (
                        id, uploader_id, diary_entry_id, purpose, kind, status, object_key,
                        original_name, content_type, expected_size, actual_size, position,
                        created_at, ready_at
                    ) VALUES (
                        '40000000-0000-4000-8000-000000000003', 1, 40,
                        'DIARY_ENTRY', 'IMAGE', 'READY', 'ready/diary-image',
                        'diary.png', 'image/png', 1024, 1024, 0,
                        TIMESTAMPTZ '2026-07-21 00:05:00Z',
                        TIMESTAMPTZ '2026-07-21 00:06:00Z'
                    )
                    """);
            execute(connection, "DELETE FROM woorisai.diary_entry WHERE id = 40");
            assertThat(queryInt(connection, """
                    SELECT COUNT(*)
                    FROM woorisai.media_attachment
                    WHERE id = '40000000-0000-4000-8000-000000000003'
                    """))
                    .isZero();
        }
    }

    private static Flyway flyway() {
        return Flyway.configure()
                .dataSource(POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword())
                .locations("classpath:db/migration/postgresql")
                .schemas("woorisai")
                .defaultSchema("woorisai")
                .createSchemas(true)
                .baselineOnMigrate(false)
                .load();
    }

    private static Flyway flywayAt(MigrationVersion target) {
        return Flyway.configure()
                .dataSource(POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword())
                .locations("classpath:db/migration/postgresql")
                .schemas("woorisai")
                .defaultSchema("woorisai")
                .createSchemas(true)
                .baselineOnMigrate(false)
                .target(target)
                .load();
    }

    private static Connection connection() throws SQLException {
        return DriverManager.getConnection(
                POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword());
    }

    private void insertCanonicalParticipants(Connection connection) throws SQLException {
        try (var statement = connection.prepareStatement("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, ?, ?, ?)
                """)) {
            OffsetDateTime createdAt = OffsetDateTime.of(
                    2026, 7, 21, 0, 0, 0, 0, ZoneOffset.UTC);
            for (int slot = 1; slot <= 2; slot++) {
                statement.setLong(1, slot);
                statement.setInt(2, slot);
                statement.setString(3, "participant-" + slot);
                statement.setObject(4, createdAt);
                statement.addBatch();
            }
            statement.executeBatch();
        }
    }

    private void assertConstraintViolation(
            Connection connection,
            String sqlState,
            String constraintName,
            String sql
    ) {
        assertThatThrownBy(() -> execute(connection, sql))
                .isInstanceOfSatisfying(SQLException.class, exception -> {
                    assertThat(exception.getSQLState()).isEqualTo(sqlState);
                    assertThat(exception.getMessage()).contains(constraintName);
                });
    }

    private static void execute(Connection connection, String sql) throws SQLException {
        try (var statement = connection.createStatement()) {
            statement.executeUpdate(sql);
        }
    }

    private List<String> queryStrings(Connection connection, String sql) throws SQLException {
        try (var statement = connection.createStatement(); var resultSet = statement.executeQuery(sql)) {
            var result = new java.util.ArrayList<String>();
            while (resultSet.next()) {
                result.add(resultSet.getString(1));
            }
            return result;
        }
    }

    private static int queryInt(Connection connection, String sql) throws SQLException {
        try (var statement = connection.createStatement(); var resultSet = statement.executeQuery(sql)) {
            resultSet.next();
            return resultSet.getInt(1);
        }
    }
}
