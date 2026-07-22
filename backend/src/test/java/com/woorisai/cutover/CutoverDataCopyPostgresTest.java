package com.woorisai.cutover;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.awaitility.Awaitility.await;

import com.woorisai.testing.WoorisaiPostgresContainer;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Duration;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.testcontainers.postgresql.PostgreSQLContainer;

@Tag("postgres")
class CutoverDataCopyPostgresTest {

    private static final PostgreSQLContainer POSTGRES = WoorisaiPostgresContainer.create();
    private static final String SOURCE_COMMIT = "94434a05474fb878e8d7debfb3a6a8926a1825d8";
    private static final String SYNTHETIC_PIN_HASH =
            "{bcrypt}$2a$10$" + "A".repeat(53);

    @TempDir
    Path temporaryDirectory;

    @BeforeAll
    static void startPostgres() {
        POSTGRES.start();
    }

    @AfterAll
    static void stopPostgres() {
        POSTGRES.stop();
    }

    @BeforeEach
    void prepareSchemas() throws Exception {
        try (Connection connection = connection()) {
            execute(connection, "DROP SCHEMA IF EXISTS legacy CASCADE");
            execute(connection, "DROP SCHEMA IF EXISTS woorisai CASCADE");
        }
        Flyway.configure()
                .dataSource(POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword())
                .defaultSchema("woorisai")
                .schemas("woorisai")
                .createSchemas(true)
                .baselineOnMigrate(false)
                .locations("classpath:db/migration/postgresql")
                .load()
                .migrate();
        try (Connection connection = connection()) {
            createLegacySchema(connection);
            insertValidSourceDataset(connection);
        }
    }

    @Test
    void defaultDryRunVerifiesTheWholeCopyAndRollsBackRowsAndSequences() throws Exception {
        DataCopyReport report = new CutoverDataCopy().execute(config(false, inventory()));

        assertThat(report.committed()).isFalse();
        assertThat(report.rowCounts())
                .containsEntry("participant", 2L)
                .containsEntry("participant_credential", 2L)
                .containsEntry("relationship_score", 2L)
                .containsEntry("score_change", 1L)
                .containsEntry("score_change_comment", 1L)
                .containsEntry("diary_entry", 1L)
                .containsEntry("diary_entry_comment", 1L)
                .containsEntry("media_attachment", 4L);

        try (Connection connection = connection()) {
            assertTargetEmpty(connection);
            assertThat(queryLong(connection, """
                    SELECT last_value
                    FROM woorisai.diary_entry_id_seq
                    """)).isOne();
            assertThat(queryBoolean(connection, """
                    SELECT is_called
                    FROM woorisai.diary_entry_id_seq
                    """)).isFalse();
        }
    }

    @Test
    void explicitCommitCopiesSyntheticDatasetAndRestartsEveryIdentityAtNextValue()
            throws Exception {
        DataCopyReport report = new CutoverDataCopy().execute(config(true, inventory()));

        assertThat(report.committed()).isTrue();
        try (Connection connection = connection()) {
            assertThat(queryLong(connection,
                    "SELECT COUNT(*) FROM woorisai.participant")).isEqualTo(2);
            assertThat(queryLong(connection,
                    "SELECT COUNT(*) FROM woorisai.participant_credential")).isEqualTo(2);
            assertThat(queryLong(connection, """
                    SELECT COUNT(*)
                    FROM woorisai.flyway_schema_history
                    WHERE (version = '1' AND checksum = -1427245241)
                       OR (version = '2' AND checksum = -345802610)
                    """)).isEqualTo(2);
            assertThat(queryLong(connection, """
                    SELECT COUNT(*)
                    FROM woorisai.relationship_score
                    WHERE version = 0
                    """)).isEqualTo(2);
            assertThat(queryLong(connection, """
                    SELECT COUNT(*)
                    FROM woorisai.score_change
                    WHERE reason IS NULL
                    """)).isOne();
            assertThat(queryLong(connection, """
                    SELECT COUNT(*)
                    FROM woorisai.score_change_comment
                    WHERE content IS NULL
                    """)).isOne();
            assertThat(queryLong(connection, """
                    SELECT COUNT(*)
                    FROM woorisai.media_attachment
                    WHERE status = 'READY'
                      AND actual_size = expected_size
                    """)).isEqualTo(4);

            assertThat(nextValue(connection, "participant")).isEqualTo(21);
            assertThat(nextValue(connection, "relationship_score")).isEqualTo(201);
            assertThat(nextValue(connection, "score_change")).isEqualTo(1001);
            assertThat(nextValue(connection, "score_change_comment")).isEqualTo(2001);
            assertThat(nextValue(connection, "diary_entry")).isEqualTo(3001);
            assertThat(nextValue(connection, "diary_entry_comment")).isEqualTo(4001);
            assertThat(nextValue(connection, "notification_fid")).isOne();
        }
    }

    @Test
    void waitsForTheFrozenSourceLockBeforeTakingItsRepeatableReadSnapshot() throws Exception {
        var executor = Executors.newSingleThreadExecutor();
        try (Connection writer = connection()) {
            writer.setAutoCommit(false);
            execute(writer, """
                    UPDATE legacy.relationship_score
                    SET current_score = 61, updated_at = TIMESTAMPTZ '2026-07-19 00:02:00Z'
                    WHERE id = 100
                    """);
            execute(writer, """
                    UPDATE legacy.score_change
                    SET delta = 11, resulting_score = 61
                    WHERE id = 1000
                    """);

            var copy = executor.submit(() ->
                    new CutoverDataCopy().execute(config(true, inventory())));
            await()
                    .pollInterval(Duration.ofMillis(25))
                    .atMost(Duration.ofSeconds(5))
                    .until(CutoverDataCopyPostgresTest::cutoverIsWaitingOnLock);

            writer.commit();
            assertThat(copy.get(10, TimeUnit.SECONDS).committed()).isTrue();
        } finally {
            executor.shutdownNow();
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }

        try (Connection connection = connection()) {
            assertThat(queryLong(connection, """
                    SELECT current_score
                    FROM woorisai.relationship_score
                    WHERE id = 100
                    """)).isEqualTo(61);
            assertThat(queryLong(connection, """
                    SELECT resulting_score
                    FROM woorisai.score_change
                    WHERE id = 1000
                    """)).isEqualTo(61);
        }
    }

    @Test
    void sourceCommitAndDjangoMigrationDriftFailClosed() throws Exception {
        Path inventory = inventory();
        assertThatThrownBy(() -> new CutoverConfig(
                POSTGRES.getJdbcUrl(),
                POSTGRES.getUsername(),
                POSTGRES.getPassword(),
                "legacy",
                "5445426a93dbb095634748055d1af6e48a5e5468",
                SOURCE_COMMIT,
                SYNTHETIC_PIN_HASH,
                SYNTHETIC_PIN_HASH,
                inventory,
                false,
                null))
                .isInstanceOf(CutoverException.class)
                .hasMessageContaining("commits do not match");

        assertThatThrownBy(() -> new CutoverConfig(
                POSTGRES.getJdbcUrl(),
                POSTGRES.getUsername(),
                POSTGRES.getPassword(),
                "legacy",
                "5445426a93dbb095634748055d1af6e48a5e5468",
                "5445426a93dbb095634748055d1af6e48a5e5468",
                SYNTHETIC_PIN_HASH,
                SYNTHETIC_PIN_HASH,
                inventory,
                false,
                null))
                .isInstanceOf(CutoverException.class)
                .hasMessageContaining("reviewed baseline");

        try (Connection connection = connection()) {
            execute(connection, """
                    UPDATE legacy.django_migrations
                    SET name = '0012_unapproved_drift'
                    WHERE app = 'ratings'
                    """);
        }

        assertThatThrownBy(() -> new CutoverDataCopy().execute(config(false, inventory)))
                .isInstanceOf(CutoverException.class)
                .hasMessageContaining("migration head has drifted");
        try (Connection connection = connection()) {
            assertTargetEmpty(connection);
        }
    }

    @Test
    void invalidAttachedMediaAuthorTopologyFailsBeforeCopy() throws Exception {
        try (Connection connection = connection()) {
            execute(connection, """
                    UPDATE legacy.media_attachment
                    SET uploader_id = 20
                    WHERE object_key = 'final/diary-0'
                    """);
        }

        assertThatThrownBy(() -> new CutoverDataCopy().execute(config(false, inventory())))
                .isInstanceOf(CutoverException.class)
                .hasMessageContaining("invalid parent, uploader");
        try (Connection connection = connection()) {
            assertTargetEmpty(connection);
        }
    }

    @Test
    void unverifiedR2InventoryPreventsExplicitCommit() throws Exception {
        Path inventory = inventory();
        Files.writeString(inventory, Files.readString(inventory)
                .replace("final/score\timage/jpeg\t100\tetag-score",
                        "final/score\timage/jpeg\t101\tetag-score"));

        assertThatThrownBy(() -> new CutoverDataCopy().execute(config(true, inventory)))
                .isInstanceOf(CutoverException.class)
                .hasMessageContaining("failed inventory verification");
        try (Connection connection = connection()) {
            assertTargetEmpty(connection);
        }
    }

    @Test
    void failureAfterEarlyInsertsRollsBackTheEntireTargetTransaction() throws Exception {
        try (Connection connection = connection()) {
            execute(connection, """
                    CREATE FUNCTION woorisai.reject_synthetic_score_copy()
                    RETURNS trigger
                    LANGUAGE plpgsql
                    AS $$
                    BEGIN
                        RAISE EXCEPTION 'synthetic score copy failure';
                    END
                    $$
                    """);
            execute(connection, """
                    CREATE TRIGGER reject_synthetic_score_copy
                    BEFORE INSERT ON woorisai.score_change
                    FOR EACH ROW EXECUTE FUNCTION woorisai.reject_synthetic_score_copy()
                    """);
        }

        assertThatThrownBy(() -> new CutoverDataCopy().execute(config(true, inventory())))
                .isInstanceOf(CutoverException.class)
                .hasMessageContaining("copy transaction failed");
        try (Connection connection = connection()) {
            assertTargetEmpty(connection);
        }
    }

    @Test
    void commitIsDeniedWithoutBothTheArgumentModeAndExactApproval() throws Exception {
        Path inventory = inventory();
        assertThatThrownBy(() -> new CutoverConfig(
                POSTGRES.getJdbcUrl(),
                POSTGRES.getUsername(),
                POSTGRES.getPassword(),
                "legacy",
                SOURCE_COMMIT,
                SOURCE_COMMIT,
                SYNTHETIC_PIN_HASH,
                SYNTHETIC_PIN_HASH,
                inventory,
                true,
                "not-approved"))
                .isInstanceOf(CutoverException.class)
                .hasMessageContaining("explicit one-transaction copy approval");
    }

    private CutoverConfig config(boolean commit, Path inventory) {
        return new CutoverConfig(
                POSTGRES.getJdbcUrl(),
                POSTGRES.getUsername(),
                POSTGRES.getPassword(),
                "legacy",
                SOURCE_COMMIT,
                SOURCE_COMMIT,
                SYNTHETIC_PIN_HASH,
                SYNTHETIC_PIN_HASH,
                inventory,
                commit,
                commit ? CutoverConfig.COMMIT_APPROVAL : null);
    }

    private Path inventory() throws IOException {
        Path inventory = temporaryDirectory.resolve("private-r2-inventory.tsv");
        Files.writeString(inventory, """
                object_key\tcontent_type\tsize\tetag
                final/score\timage/jpeg\t100\tetag-score
                final/comment\tvideo/mp4\t1000\tetag-comment
                final/diary-0\timage/png\t200\tetag-diary-0
                final/diary-1\timage/webp\t300\tetag-diary-1
                """);
        return inventory;
    }

    private static void createLegacySchema(Connection connection) throws SQLException {
        execute(connection, "CREATE SCHEMA legacy");
        execute(connection, """
                CREATE TABLE legacy.django_migrations (
                    id BIGINT PRIMARY KEY,
                    app VARCHAR(255) NOT NULL,
                    name VARCHAR(255) NOT NULL,
                    applied TIMESTAMPTZ NOT NULL
                )
                """);
        execute(connection, """
                CREATE TABLE legacy.participant (
                    id BIGINT PRIMARY KEY,
                    user_id BIGINT NOT NULL,
                    display_name VARCHAR(30) NOT NULL,
                    slot SMALLINT NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL
                )
                """);
        execute(connection, """
                CREATE TABLE legacy.relationship_score (
                    id BIGINT PRIMARY KEY,
                    source_participant_id BIGINT NOT NULL,
                    target_participant_id BIGINT NOT NULL,
                    current_score SMALLINT NOT NULL,
                    updated_at TIMESTAMPTZ NOT NULL
                )
                """);
        execute(connection, """
                CREATE TABLE legacy.score_change (
                    id BIGINT PRIMARY KEY,
                    relationship_score_id BIGINT NOT NULL,
                    changed_by_id BIGINT NOT NULL,
                    delta SMALLINT NOT NULL,
                    reason VARCHAR(200) NOT NULL,
                    resulting_score SMALLINT NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL
                )
                """);
        execute(connection, """
                CREATE TABLE legacy.score_change_comment (
                    id BIGINT PRIMARY KEY,
                    score_change_id BIGINT NOT NULL,
                    author_id BIGINT NOT NULL,
                    content VARCHAR(500) NOT NULL,
                    media_count SMALLINT NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL
                )
                """);
        execute(connection, """
                CREATE TABLE legacy.diary_entry (
                    id BIGINT PRIMARY KEY,
                    author_id BIGINT NOT NULL,
                    content VARCHAR(1000) NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL,
                    updated_at TIMESTAMPTZ
                )
                """);
        execute(connection, """
                CREATE TABLE legacy.diary_entry_comment (
                    id BIGINT PRIMARY KEY,
                    diary_entry_id BIGINT NOT NULL,
                    author_id BIGINT NOT NULL,
                    content VARCHAR(500) NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL
                )
                """);
        execute(connection, """
                CREATE TABLE legacy.media_attachment (
                    id UUID PRIMARY KEY,
                    uploader_id BIGINT NOT NULL,
                    score_change_id BIGINT,
                    comment_id BIGINT,
                    diary_entry_id BIGINT,
                    purpose VARCHAR(20) NOT NULL,
                    kind VARCHAR(10) NOT NULL,
                    status VARCHAR(12) NOT NULL,
                    object_key VARCHAR(255) NOT NULL,
                    original_name VARCHAR(255) NOT NULL,
                    content_type VARCHAR(100) NOT NULL,
                    expected_size BIGINT NOT NULL,
                    actual_size BIGINT,
                    etag VARCHAR(255) NOT NULL,
                    expires_at TIMESTAMPTZ NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL,
                    finalized_at TIMESTAMPTZ,
                    finalization_token UUID,
                    position SMALLINT NOT NULL
                )
                """);
    }

    private static void insertValidSourceDataset(Connection connection) throws SQLException {
        execute(connection, """
                INSERT INTO legacy.django_migrations (id, app, name, applied)
                VALUES (11, 'ratings', '0011_diaryentrycomment', TIMESTAMPTZ '2026-07-20 00:00:00Z')
                """);
        execute(connection, """
                INSERT INTO legacy.participant (id, user_id, display_name, slot, created_at)
                VALUES
                    (10, 10010, 'Synthetic One', 1, TIMESTAMPTZ '2026-07-18 00:00:00Z'),
                    (20, 10020, 'Synthetic Two', 2, TIMESTAMPTZ '2026-07-18 00:00:01Z')
                """);
        execute(connection, """
                INSERT INTO legacy.relationship_score (
                    id, source_participant_id, target_participant_id, current_score, updated_at
                ) VALUES
                    (100, 10, 20, 60, TIMESTAMPTZ '2026-07-19 00:00:00Z'),
                    (200, 20, 10, 40, TIMESTAMPTZ '2026-07-19 00:00:01Z')
                """);
        execute(connection, """
                INSERT INTO legacy.score_change (
                    id, relationship_score_id, changed_by_id, delta,
                    reason, resulting_score, created_at
                ) VALUES (
                    1000, 100, 10, 10, '', 60, TIMESTAMPTZ '2026-07-19 00:00:00Z'
                )
                """);
        execute(connection, """
                INSERT INTO legacy.score_change_comment (
                    id, score_change_id, author_id, content, media_count, created_at
                ) VALUES (
                    2000, 1000, 20, '', 1, TIMESTAMPTZ '2026-07-19 00:00:01Z'
                )
                """);
        execute(connection, """
                INSERT INTO legacy.diary_entry (
                    id, author_id, content, created_at, updated_at
                ) VALUES (
                    3000, 10, 'Synthetic diary',
                    TIMESTAMPTZ '2026-07-19 00:00:02Z',
                    TIMESTAMPTZ '2026-07-19 00:00:03Z'
                )
                """);
        execute(connection, """
                INSERT INTO legacy.diary_entry_comment (
                    id, diary_entry_id, author_id, content, created_at
                ) VALUES (
                    4000, 3000, 20, 'Synthetic diary comment',
                    TIMESTAMPTZ '2026-07-19 00:00:04Z'
                )
                """);
        execute(connection, """
                INSERT INTO legacy.media_attachment (
                    id, uploader_id, score_change_id, comment_id, diary_entry_id,
                    purpose, kind, status, object_key, original_name, content_type,
                    expected_size, actual_size, etag, expires_at, created_at,
                    finalized_at, finalization_token, position
                ) VALUES
                    ('10000000-0000-4000-8000-000000000001', 10, 1000, NULL, NULL,
                     'score_change', 'image', 'attached', 'final/score', 'score.jpg',
                     'image/jpeg', 100, 100, 'etag-score',
                     TIMESTAMPTZ '2026-08-01 00:00:00Z', TIMESTAMPTZ '2026-07-19 00:00:00Z',
                     TIMESTAMPTZ '2026-07-19 00:01:00Z', NULL, 0),
                    ('10000000-0000-4000-8000-000000000002', 20, 1000, 2000, NULL,
                     'comment', 'video', 'attached', 'final/comment', 'comment.mp4',
                     'video/mp4', 1000, 1000, 'etag-comment',
                     TIMESTAMPTZ '2026-08-01 00:00:00Z', TIMESTAMPTZ '2026-07-19 00:00:01Z',
                     TIMESTAMPTZ '2026-07-19 00:01:01Z', NULL, 0),
                    ('10000000-0000-4000-8000-000000000003', 10, NULL, NULL, 3000,
                     'diary_entry', 'image', 'attached', 'final/diary-0', 'diary-0.png',
                     'image/png', 200, 200, 'etag-diary-0',
                     TIMESTAMPTZ '2026-08-01 00:00:00Z', TIMESTAMPTZ '2026-07-19 00:00:02Z',
                     TIMESTAMPTZ '2026-07-19 00:01:02Z', NULL, 0),
                    ('10000000-0000-4000-8000-000000000004', 10, NULL, NULL, 3000,
                     'diary_entry', 'image', 'attached', 'final/diary-1', 'diary-1.webp',
                     'image/webp', 300, 300, 'etag-diary-1',
                     TIMESTAMPTZ '2026-08-01 00:00:00Z', TIMESTAMPTZ '2026-07-19 00:00:03Z',
                     TIMESTAMPTZ '2026-07-19 00:01:03Z', NULL, 1)
                """);
    }

    private static void assertTargetEmpty(Connection connection) throws SQLException {
        assertThat(queryLong(connection, """
                SELECT (SELECT COUNT(*) FROM woorisai.participant)
                     + (SELECT COUNT(*) FROM woorisai.participant_credential)
                     + (SELECT COUNT(*) FROM woorisai.relationship_score)
                     + (SELECT COUNT(*) FROM woorisai.score_change)
                     + (SELECT COUNT(*) FROM woorisai.score_change_comment)
                     + (SELECT COUNT(*) FROM woorisai.diary_entry)
                     + (SELECT COUNT(*) FROM woorisai.diary_entry_comment)
                     + (SELECT COUNT(*) FROM woorisai.media_attachment)
                     + (SELECT COUNT(*) FROM woorisai.notification_fid)
                     + (SELECT COUNT(*) FROM woorisai.event_publication)
                """)).isZero();
    }

    private static boolean cutoverIsWaitingOnLock() throws SQLException {
        try (Connection connection = connection()) {
            return queryLong(connection, """
                    SELECT COUNT(*)
                    FROM pg_stat_activity
                    WHERE application_name = 'woorisai-cutover-data-copy'
                      AND wait_event_type = 'Lock'
                    """) == 1;
        }
    }

    private static long nextValue(Connection connection, String table) throws SQLException {
        return queryLong(
                connection,
                "SELECT nextval(pg_get_serial_sequence('woorisai." + table + "', 'id'))");
    }

    private static Connection connection() throws SQLException {
        return DriverManager.getConnection(
                POSTGRES.getJdbcUrl(),
                POSTGRES.getUsername(),
                POSTGRES.getPassword());
    }

    private static void execute(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement()) {
            statement.execute(sql);
        }
    }

    private static long queryLong(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement();
                ResultSet result = statement.executeQuery(sql)) {
            result.next();
            return result.getLong(1);
        }
    }

    private static boolean queryBoolean(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement();
                ResultSet result = statement.executeQuery(sql)) {
            result.next();
            return result.getBoolean(1);
        }
    }
}
