package com.woorisai.testing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

class CleanSchemaH2MigrationTest {

    private String jdbcUrl;
    private Connection databaseKeeper;
    private Flyway flyway;

    @BeforeEach
    void migrateEmptyDatabase() throws SQLException {
        jdbcUrl = "jdbc:h2:mem:clean-schema-" + UUID.randomUUID()
                + ";MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE";
        databaseKeeper = DriverManager.getConnection(jdbcUrl, "sa", "");
        var dataSource = new SingleConnectionDataSource(databaseKeeper, true);
        flyway = Flyway.configure()
                .dataSource(dataSource)
                .locations("classpath:db/migration/h2")
                .schemas("woorisai")
                .defaultSchema("woorisai")
                .createSchemas(true)
                .baselineOnMigrate(false)
                .load();

        var result = flyway.migrate();

        assertThat(result.migrationsExecuted).isEqualTo(2);
    }

    @AfterEach
    void closeDatabase() throws SQLException {
        databaseKeeper.close();
    }

    @Test
    void createsOnlyTheCurrentCleanSpringSchema() throws Exception {
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

            assertThat(queryInt(connection, """
                    SELECT COUNT(*)
                    FROM information_schema.tables
                    WHERE table_schema = 'public'
                      AND table_name IN ('participant', 'app_access_token', 'access_token')
                    """))
                    .isZero();

            assertThat(queryStrings(connection, """
                    SELECT table_name || ':' || lower(data_type) || ':' || is_nullable
                    FROM information_schema.columns
                    WHERE table_schema = 'woorisai'
                      AND table_name IN (
                          'relationship_score', 'diary_entry', 'diary_entry_comment'
                      )
                      AND column_name = 'version'
                    ORDER BY table_name
                    """))
                    .containsExactly(
                            "diary_entry:bigint:NO",
                            "diary_entry_comment:bigint:NO",
                            "relationship_score:bigint:NO"
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
                    SELECT index_name || ':' || column_name || ':' || ordinal_position
                    FROM information_schema.index_columns
                    WHERE index_schema = 'woorisai'
                      AND table_name = 'event_publication'
                      AND index_name IN (
                          'event_publication_by_listener_and_serialized_event_idx',
                          'event_publication_by_completion_date_idx'
                      )
                    ORDER BY index_name, ordinal_position
                    """))
                    .containsExactly(
                            "event_publication_by_completion_date_idx:completion_date:1",
                            "event_publication_by_listener_and_serialized_event_idx:listener_id:1",
                            "event_publication_by_listener_and_serialized_event_idx:serialized_event:2"
                    );
        }

        assertThat(flyway.migrate().migrationsExecuted).isZero();
    }

    @Test
    void requiresLegacyEmptyReasonAndMediaOnlyCommentTextToBeCopiedAsNull() throws Exception {
        try (Connection connection = connection()) {
            insertCanonicalParticipants(connection);

            assertConstraintViolation(connection, "23513", "participant_slot_ck", """
                    INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                    VALUES (3, 3, 'invalid-slot', TIMESTAMP WITH TIME ZONE '2026-07-21 00:00:00Z')
                    """);

            execute(connection, """
                    INSERT INTO woorisai.relationship_score (
                        id, source_participant_id, target_participant_id, current_score, updated_at
                    ) VALUES (
                        10, 1, 2, 50, TIMESTAMP WITH TIME ZONE '2026-07-21 00:00:00Z'
                    )
                    """);

            assertConstraintViolation(connection, "23513", "relationship_score_value_ck", """
                    INSERT INTO woorisai.relationship_score (
                        id, source_participant_id, target_participant_id, current_score, updated_at
                    ) VALUES (
                        11, 2, 1, 101, TIMESTAMP WITH TIME ZONE '2026-07-21 00:00:00Z'
                    )
                    """);

            execute(connection, """
                    INSERT INTO woorisai.score_change (
                        id, relationship_score_id, changed_by_id, delta,
                        resulting_score, reason, created_at
                    ) VALUES (
                        20, 10, 1, 5, 55, NULL,
                        TIMESTAMP WITH TIME ZONE '2026-07-21 00:01:00Z'
                    )
                    """);
            assertThat(queryInt(connection, """
                    SELECT COUNT(*)
                    FROM woorisai.score_change
                    WHERE id = 20 AND reason IS NULL
                    """))
                    .isOne();
            assertConstraintViolation(connection, "23513", "score_change_reason_ck", """
                    INSERT INTO woorisai.score_change (
                        id, relationship_score_id, changed_by_id, delta,
                        resulting_score, reason, created_at
                    ) VALUES (
                        21, 10, 1, 5, 55, '',
                        TIMESTAMP WITH TIME ZONE '2026-07-21 00:01:00Z'
                    )
                    """);

            execute(connection, """
                    INSERT INTO woorisai.score_change_comment (
                        id, score_change_id, author_id, content, created_at
                    ) VALUES (
                        30, 20, 2, NULL,
                        TIMESTAMP WITH TIME ZONE '2026-07-21 00:02:00Z'
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
                    "23513",
                    "score_change_comment_content_ck",
                    """
                            INSERT INTO woorisai.score_change_comment (
                                id, score_change_id, author_id, content, created_at
                            ) VALUES (
                                31, 20, 2, '',
                                TIMESTAMP WITH TIME ZONE '2026-07-21 00:02:00Z'
                            )
                            """
            );

            assertConstraintViolation(connection, "23513", "media_attachment_object_key_ck", """
                    INSERT INTO woorisai.media_attachment (
                        id, uploader_id, purpose, kind, status, object_key, original_name,
                        content_type, expected_size, position, created_at
                    ) VALUES (
                        '40000000-0000-4000-8000-000000000009', 1,
                        'DIARY_ENTRY', 'IMAGE', 'PENDING', '   ', 'blank.png',
                        'image/png', 1024, 0,
                        TIMESTAMP WITH TIME ZONE '2026-07-21 00:00:00Z'
                    )
                    """);

            UUID mediaId = UUID.fromString("40000000-0000-4000-8000-000000000001");
            execute(connection, """
                    INSERT INTO woorisai.media_attachment (
                        id, uploader_id, purpose, kind, status, object_key, original_name,
                        content_type, expected_size, position, created_at
                    ) VALUES (
                        '%s', 1, 'SCORE_CHANGE_COMMENT', 'IMAGE', 'PENDING',
                        'pending/portable-image', 'image.png', 'image/png', 1024, 0,
                        TIMESTAMP WITH TIME ZONE '2026-07-21 00:00:00Z'
                    )
                    """.formatted(mediaId));

            assertConstraintViolation(connection, "23513", "media_attachment_state_ck", """
                    UPDATE woorisai.media_attachment
                    SET status = 'READY', actual_size = 1024
                    WHERE id = '%s'
                    """.formatted(mediaId));
        }
    }

    private Connection connection() throws SQLException {
        return DriverManager.getConnection(jdbcUrl, "sa", "");
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

    private void execute(Connection connection, String sql) throws SQLException {
        try (var statement = connection.createStatement()) {
            statement.executeUpdate(sql);
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
                    assertThat(exception.getMessage().toLowerCase(Locale.ROOT))
                            .contains(constraintName);
                });
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

    private int queryInt(Connection connection, String sql) throws SQLException {
        try (var statement = connection.createStatement(); var resultSet = statement.executeQuery(sql)) {
            resultSet.next();
            return resultSet.getInt(1);
        }
    }
}
