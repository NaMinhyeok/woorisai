package com.woorisai.cutover;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.Set;

final class CutoverDataCopy {

    private static final String TARGET_SCHEMA = "woorisai";
    private static final String EXPECTED_DJANGO_HEAD = "0011_diaryentrycomment";
    private static final long ADVISORY_LOCK_KEY = 8_779_715_241L;

    private static final List<String> SOURCE_TABLES = List.of(
            "django_migrations",
            "participant",
            "relationship_score",
            "score_change",
            "score_change_comment",
            "diary_entry",
            "diary_entry_comment",
            "media_attachment");

    private static final List<String> TARGET_DATA_TABLES = List.of(
            "participant",
            "participant_credential",
            "relationship_score",
            "score_change",
            "score_change_comment",
            "diary_entry",
            "diary_entry_comment",
            "media_attachment",
            "notification_fid",
            "event_publication");

    private static final List<String> IDENTITY_TABLES = List.of(
            "participant",
            "relationship_score",
            "score_change",
            "score_change_comment",
            "diary_entry",
            "diary_entry_comment",
            "notification_fid");

    private static final Map<String, Set<String>> SOURCE_COLUMNS = orderedColumns(
            entry("django_migrations", "id", "app", "name", "applied"),
            entry("participant", "id", "user_id", "display_name", "slot", "created_at"),
            entry(
                    "relationship_score",
                    "id",
                    "source_participant_id",
                    "target_participant_id",
                    "current_score",
                    "updated_at"),
            entry(
                    "score_change",
                    "id",
                    "relationship_score_id",
                    "changed_by_id",
                    "delta",
                    "reason",
                    "resulting_score",
                    "created_at"),
            entry(
                    "score_change_comment",
                    "id",
                    "score_change_id",
                    "author_id",
                    "content",
                    "media_count",
                    "created_at"),
            entry(
                    "diary_entry",
                    "id",
                    "author_id",
                    "content",
                    "created_at",
                    "updated_at"),
            entry(
                    "diary_entry_comment",
                    "id",
                    "diary_entry_id",
                    "author_id",
                    "content",
                    "created_at"),
            entry(
                    "media_attachment",
                    "id",
                    "uploader_id",
                    "score_change_id",
                    "comment_id",
                    "diary_entry_id",
                    "purpose",
                    "kind",
                    "status",
                    "object_key",
                    "original_name",
                    "content_type",
                    "expected_size",
                    "actual_size",
                    "etag",
                    "expires_at",
                    "created_at",
                    "finalized_at",
                    "finalization_token",
                    "position"));

    private static final Map<String, Set<String>> TARGET_COLUMNS = orderedColumns(
            entry("flyway_schema_history", "installed_rank", "version", "description", "type", "script",
                    "checksum", "installed_by", "installed_on", "execution_time", "success"),
            entry("participant", "id", "slot", "display_name", "created_at"),
            entry("participant_credential", "participant_id", "pin_hash", "updated_at"),
            entry(
                    "relationship_score",
                    "id",
                    "source_participant_id",
                    "target_participant_id",
                    "current_score",
                    "updated_at",
                    "version"),
            entry(
                    "score_change",
                    "id",
                    "relationship_score_id",
                    "changed_by_id",
                    "delta",
                    "resulting_score",
                    "reason",
                    "created_at"),
            entry(
                    "score_change_comment",
                    "id",
                    "score_change_id",
                    "author_id",
                    "content",
                    "created_at"),
            entry(
                    "diary_entry",
                    "id",
                    "author_id",
                    "content",
                    "created_at",
                    "updated_at",
                    "version"),
            entry(
                    "diary_entry_comment",
                    "id",
                    "diary_entry_id",
                    "author_id",
                    "content",
                    "created_at",
                    "updated_at",
                    "version"),
            entry(
                    "media_attachment",
                    "id",
                    "uploader_id",
                    "score_change_id",
                    "score_change_comment_id",
                    "diary_entry_id",
                    "purpose",
                    "kind",
                    "status",
                    "object_key",
                    "original_name",
                    "content_type",
                    "expected_size",
                    "actual_size",
                    "position",
                    "created_at",
                    "ready_at"),
            entry("notification_fid", "id", "participant_id", "fid", "created_at"),
            entry(
                    "event_publication",
                    "id",
                    "listener_id",
                    "event_type",
                    "serialized_event",
                    "publication_date",
                    "completion_date",
                    "status",
                    "completion_attempts",
                    "last_resubmission_date"));

    DataCopyReport execute(CutoverConfig config) {
        R2Inventory inventory = R2Inventory.read(config.r2InventoryPath());
        Properties credentials = new Properties();
        credentials.setProperty("user", config.databaseUser());
        credentials.setProperty("password", config.databasePassword());
        credentials.setProperty("ApplicationName", "woorisai-cutover-data-copy");

        try (Connection connection = DriverManager.getConnection(config.jdbcUrl(), credentials)) {
            connection.setAutoCommit(false);
            connection.setTransactionIsolation(Connection.TRANSACTION_REPEATABLE_READ);
            try {
                configureTimeouts(connection);
                lockTables(connection, config.sourceSchema(), SOURCE_TABLES, "SHARE");
                lockTables(
                        connection,
                        TARGET_SCHEMA,
                        List.of("flyway_schema_history"),
                        "SHARE");
                lockTables(connection, TARGET_SCHEMA, TARGET_DATA_TABLES, "ACCESS EXCLUSIVE");
                acquireOperatorLock(connection);
                validateSchema(connection, config.sourceSchema(), SOURCE_COLUMNS, false);
                validateSchema(connection, TARGET_SCHEMA, TARGET_COLUMNS, true);
                validateSourceMigrationHead(connection, config.sourceSchema());
                validateTargetFlyway(connection);
                validateTargetEmpty(connection);
                validateSourceData(connection, config.sourceSchema());
                verifyR2Inventory(connection, config.sourceSchema(), inventory);

                Map<String, Long> counts = copyRows(connection, config);
                resetIdentitySequences(connection);
                validateCopiedData(connection, config, counts);
                validateSequences(connection);

                if (config.commit()) {
                    connection.commit();
                } else {
                    connection.rollback();
                }
                return new DataCopyReport(config.commit(), counts);
            } catch (SQLException | RuntimeException exception) {
                rollback(connection, exception);
                if (exception instanceof CutoverException cutoverException) {
                    throw cutoverException;
                }
                if (exception instanceof SQLException sqlException) {
                    throw new CutoverException("The PostgreSQL copy transaction failed", sqlException);
                }
                throw exception;
            }
        } catch (SQLException exception) {
            throw new CutoverException("The PostgreSQL cutover connection failed", exception);
        }
    }

    private void configureTimeouts(Connection connection) throws SQLException {
        execute(connection, "SET LOCAL lock_timeout = '5s'");
        execute(connection, "SET LOCAL statement_timeout = '5min'");
    }

    private void acquireOperatorLock(Connection connection) throws SQLException {
        try (PreparedStatement statement = connection.prepareStatement(
                "SELECT pg_advisory_xact_lock(?)")) {
            statement.setLong(1, ADVISORY_LOCK_KEY);
            statement.execute();
        }
    }

    private void validateSchema(
            Connection connection,
            String schema,
            Map<String, Set<String>> expectedColumns,
            boolean requireExactTables) throws SQLException {
        Set<String> actualTables = stringSet(
                connection,
                """
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = ? AND table_type = 'BASE TABLE'
                """,
                schema);
        if (requireExactTables && !actualTables.equals(expectedColumns.keySet())) {
            throw new CutoverException("The target schema table set does not match Flyway V1/V2");
        }
        for (Map.Entry<String, Set<String>> expected : expectedColumns.entrySet()) {
            if (!actualTables.contains(expected.getKey())) {
                throw new CutoverException("A required schema table is missing");
            }
            Set<String> actualColumns = stringSet(
                    connection,
                    """
                    SELECT column_name
                    FROM information_schema.columns
                    WHERE table_schema = ? AND table_name = ?
                    """,
                    schema,
                    expected.getKey());
            if (!actualColumns.equals(expected.getValue())) {
                throw new CutoverException("A required schema table has drifted columns");
            }
        }
    }

    private void validateSourceMigrationHead(Connection connection, String sourceSchema)
            throws SQLException {
        String source = quoted(sourceSchema);
        String head = queryString(
                connection,
                """
                SELECT name
                FROM %s.django_migrations
                WHERE app = 'ratings'
                ORDER BY id DESC
                LIMIT 1
                """.formatted(source));
        if (!EXPECTED_DJANGO_HEAD.equals(head)) {
            throw new CutoverException("The Django ratings migration head has drifted");
        }
        assertEquals(
                connection,
                "The Django migration head must be applied exactly once",
                1,
                "SELECT COUNT(*) FROM %s.django_migrations WHERE app = 'ratings' AND name = '%s'"
                        .formatted(source, EXPECTED_DJANGO_HEAD));
    }

    private void validateTargetFlyway(Connection connection) throws SQLException {
        List<String> rows = new ArrayList<>();
        try (Statement statement = connection.createStatement();
                ResultSet result = statement.executeQuery("""
                        SELECT version, script, type, success
                        FROM woorisai.flyway_schema_history
                        ORDER BY installed_rank
                        """)) {
            while (result.next()) {
                rows.add(result.getString(1)
                        + "|" + result.getString(2)
                        + "|" + result.getString(3)
                        + "|" + result.getBoolean(4));
            }
        }
        List<String> expected = List.of(
                "null|\"woorisai\"|SCHEMA|true",
                "1|V1__create_woorisai_schema.sql|SQL|true",
                "2|V2__add_optimistic_lock_versions.sql|SQL|true");
        if (!rows.equals(expected)) {
            throw new CutoverException("The target Flyway history is not exactly successful V1/V2");
        }
        assertEquals(
                connection,
                "The target Flyway migrations do not match the reviewed checksums",
                2,
                """
                SELECT COUNT(*)
                FROM woorisai.flyway_schema_history
                WHERE type = 'SQL' AND success
                  AND (
                    (version = '1'
                     AND description = 'create woorisai schema'
                     AND script = 'V1__create_woorisai_schema.sql'
                     AND checksum = -1427245241)
                    OR
                    (version = '2'
                     AND description = 'add optimistic lock versions'
                     AND script = 'V2__add_optimistic_lock_versions.sql'
                     AND checksum = -345802610)
                  )
                """);

        assertEquals(
                connection,
                "The target optimistic version columns do not match V2",
                3,
                """
                SELECT COUNT(*)
                FROM information_schema.columns
                WHERE table_schema = 'woorisai'
                  AND table_name IN ('relationship_score', 'diary_entry', 'diary_entry_comment')
                  AND column_name = 'version'
                  AND data_type = 'bigint'
                  AND is_nullable = 'NO'
                  AND column_default = '0'
                """);
    }

    private void validateTargetEmpty(Connection connection) throws SQLException {
        for (String table : TARGET_DATA_TABLES) {
            assertEquals(
                    connection,
                    "Every target data table must be empty before copy",
                    0,
                    "SELECT COUNT(*) FROM woorisai." + quoted(table));
        }
    }

    private void validateSourceData(Connection connection, String sourceSchema) throws SQLException {
        String source = quoted(sourceSchema);
        assertEquals(
                connection,
                "The source must contain exactly the canonical participant pair",
                1,
                """
                SELECT COUNT(*)
                FROM (
                    SELECT COUNT(*) AS participant_count,
                           COUNT(*) FILTER (WHERE slot = 1) AS slot_one_count,
                           COUNT(*) FILTER (WHERE slot = 2) AS slot_two_count
                    FROM %s.participant
                ) pair
                WHERE participant_count = 2 AND slot_one_count = 1 AND slot_two_count = 1
                """.formatted(source));
        assertZero(
                connection,
                "Source bigint business identifiers must be positive",
                """
                SELECT id FROM %1$s.participant WHERE id <= 0
                UNION ALL SELECT id FROM %1$s.relationship_score WHERE id <= 0
                UNION ALL SELECT id FROM %1$s.score_change WHERE id <= 0
                UNION ALL SELECT id FROM %1$s.score_change_comment WHERE id <= 0
                UNION ALL SELECT id FROM %1$s.diary_entry WHERE id <= 0
                UNION ALL SELECT id FROM %1$s.diary_entry_comment WHERE id <= 0
                """.formatted(source));
        assertEquals(
                connection,
                "The source must contain exactly two reciprocal relationship scores",
                1,
                """
                SELECT COUNT(*)
                FROM (
                    SELECT COUNT(*) AS score_count,
                           COUNT(*) FILTER (
                               WHERE source_participant_id = p1.id
                                 AND target_participant_id = p2.id
                           ) AS one_to_two,
                           COUNT(*) FILTER (
                               WHERE source_participant_id = p2.id
                                 AND target_participant_id = p1.id
                           ) AS two_to_one
                    FROM %1$s.relationship_score score
                    CROSS JOIN (SELECT id FROM %1$s.participant WHERE slot = 1) p1
                    CROSS JOIN (SELECT id FROM %1$s.participant WHERE slot = 2) p2
                ) reciprocal
                WHERE score_count = 2 AND one_to_two = 1 AND two_to_one = 1
                """.formatted(source));
        assertZero(
                connection,
                "A score change is not owned by its outgoing participant",
                """
                SELECT change.id
                FROM %1$s.score_change change
                JOIN %1$s.relationship_score score ON score.id = change.relationship_score_id
                WHERE change.changed_by_id <> score.source_participant_id
                """.formatted(source));
        assertZero(
                connection,
                "A business author is not part of the canonical participant pair",
                """
                SELECT changed_by_id FROM %1$s.score_change
                 WHERE changed_by_id NOT IN (SELECT id FROM %1$s.participant)
                UNION ALL SELECT author_id FROM %1$s.score_change_comment
                 WHERE author_id NOT IN (SELECT id FROM %1$s.participant)
                UNION ALL SELECT author_id FROM %1$s.diary_entry
                 WHERE author_id NOT IN (SELECT id FROM %1$s.participant)
                UNION ALL SELECT author_id FROM %1$s.diary_entry_comment
                 WHERE author_id NOT IN (SELECT id FROM %1$s.participant)
                """.formatted(source));
        assertZero(
                connection,
                "A current relationship score differs from its latest history result",
                """
                SELECT score.id
                FROM %1$s.relationship_score score
                WHERE EXISTS (
                    SELECT 1 FROM %1$s.score_change change
                    WHERE change.relationship_score_id = score.id
                )
                  AND score.current_score <> (
                    SELECT change.resulting_score
                    FROM %1$s.score_change change
                    WHERE change.relationship_score_id = score.id
                    ORDER BY change.created_at DESC, change.id DESC
                    LIMIT 1
                  )
                """.formatted(source));
        assertZero(
                connection,
                "Source text cannot be represented by the clean target",
                """
                SELECT id FROM %1$s.participant
                 WHERE display_name IS NULL OR char_length(btrim(display_name)) = 0
                UNION ALL SELECT id FROM %1$s.score_change
                 WHERE reason <> '' AND char_length(btrim(reason)) = 0
                UNION ALL SELECT id FROM %1$s.score_change_comment
                 WHERE content <> '' AND char_length(btrim(content)) = 0
                UNION ALL SELECT id FROM %1$s.diary_entry
                 WHERE content IS NULL OR char_length(btrim(content)) = 0
                UNION ALL SELECT id FROM %1$s.diary_entry_comment
                 WHERE content IS NULL OR char_length(btrim(content)) = 0
                """.formatted(source));
        assertZero(
                connection,
                "Source diary timestamps cannot be represented by the clean target",
                """
                SELECT id FROM %1$s.diary_entry
                 WHERE updated_at IS NOT NULL AND updated_at < created_at
                """.formatted(source));
        validateSourceMedia(connection, sourceSchema);
    }

    private void validateSourceMedia(Connection connection, String sourceSchema) throws SQLException {
        String source = quoted(sourceSchema);
        assertZero(
                connection,
                "Attached media has invalid parent, uploader, or redundant comment topology",
                """
                SELECT media.id
                FROM %1$s.media_attachment media
                LEFT JOIN %1$s.score_change score_change ON score_change.id = media.score_change_id
                LEFT JOIN %1$s.score_change_comment comment ON comment.id = media.comment_id
                LEFT JOIN %1$s.diary_entry diary ON diary.id = media.diary_entry_id
                WHERE media.status = 'attached'
                  AND NOT (
                    (media.purpose = 'score_change'
                     AND media.score_change_id IS NOT NULL
                     AND media.comment_id IS NULL
                     AND media.diary_entry_id IS NULL
                     AND media.uploader_id = score_change.changed_by_id)
                    OR
                    (media.purpose = 'comment'
                     AND media.score_change_id IS NOT NULL
                     AND media.comment_id IS NOT NULL
                     AND media.diary_entry_id IS NULL
                     AND media.score_change_id = comment.score_change_id
                     AND media.uploader_id = comment.author_id)
                    OR
                    (media.purpose = 'diary_entry'
                     AND media.score_change_id IS NULL
                     AND media.comment_id IS NULL
                     AND media.diary_entry_id IS NOT NULL
                     AND media.uploader_id = diary.author_id)
                  )
                """.formatted(source));
        assertZero(
                connection,
                "Attached media metadata is incompatible with the target media policy",
                """
                SELECT id
                FROM %1$s.media_attachment
                WHERE status = 'attached'
                  AND (
                    actual_size IS NULL
                    OR actual_size <> expected_size
                    OR finalized_at IS NULL
                    OR finalized_at < created_at
                    OR char_length(btrim(object_key)) = 0
                    OR char_length(btrim(original_name)) = 0
                    OR char_length(btrim(etag)) = 0
                    OR NOT (
                      (kind = 'image'
                       AND content_type IN ('image/jpeg', 'image/png', 'image/webp')
                       AND expected_size BETWEEN 1 AND 10485760)
                      OR
                      (kind = 'video'
                       AND purpose <> 'score_change'
                       AND content_type IN ('video/mp4', 'video/webm', 'video/quicktime')
                       AND expected_size BETWEEN 1 AND 104857600)
                    )
                  )
                """.formatted(source));
        assertZero(
                connection,
                "Attached media positions or kind cardinality violate target policy",
                """
                SELECT parent_key
                FROM (
                    SELECT purpose || ':' ||
                           COALESCE(comment_id, diary_entry_id, score_change_id)::text AS parent_key,
                           purpose,
                           COUNT(*) AS media_count,
                           COUNT(DISTINCT position) AS distinct_positions,
                           MIN(position) AS min_position,
                           MAX(position) AS max_position,
                           COUNT(*) FILTER (WHERE kind = 'image') AS images,
                           COUNT(*) FILTER (WHERE kind = 'video') AS videos
                    FROM %1$s.media_attachment
                    WHERE status = 'attached'
                    GROUP BY purpose, score_change_id, comment_id, diary_entry_id
                ) grouped
                WHERE distinct_positions <> media_count
                   OR min_position <> 0
                   OR max_position <> media_count - 1
                   OR (purpose = 'score_change' AND NOT (media_count = 1 AND images = 1))
                   OR (purpose <> 'score_change'
                       AND NOT ((videos = 0 AND images BETWEEN 1 AND 4)
                                OR (videos = 1 AND images = 0 AND media_count = 1)))
                """.formatted(source));
        assertZero(
                connection,
                "Score comment media_count differs from attached media",
                """
                SELECT comment.id
                FROM %1$s.score_change_comment comment
                LEFT JOIN %1$s.media_attachment media
                  ON media.comment_id = comment.id AND media.status = 'attached'
                GROUP BY comment.id, comment.media_count
                HAVING comment.media_count <> COUNT(media.id)
                    OR (comment.content = '' AND COUNT(media.id) = 0)
                """.formatted(source));
    }

    private void verifyR2Inventory(
            Connection connection,
            String sourceSchema,
            R2Inventory inventory) throws SQLException {
        String source = quoted(sourceSchema);
        try (Statement statement = connection.createStatement();
                ResultSet result = statement.executeQuery("""
                        SELECT object_key, content_type, actual_size, etag
                        FROM %s.media_attachment
                        WHERE status = 'attached'
                        ORDER BY id
                        """.formatted(source))) {
            while (result.next()) {
                inventory.verify(
                        result.getString("object_key"),
                        result.getString("content_type"),
                        result.getLong("actual_size"),
                        result.getString("etag"));
            }
        }
    }

    private Map<String, Long> copyRows(Connection connection, CutoverConfig config)
            throws SQLException {
        String source = quoted(config.sourceSchema());
        Map<String, Long> counts = new LinkedHashMap<>();
        counts.put("participant", update(connection, """
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                SELECT id, slot, display_name, created_at
                FROM %s.participant
                ORDER BY id
                """.formatted(source)));

        try (PreparedStatement statement = connection.prepareStatement("""
                INSERT INTO woorisai.participant_credential (
                    participant_id, pin_hash, updated_at
                )
                SELECT id,
                       CASE slot WHEN 1 THEN ? WHEN 2 THEN ? END,
                       CURRENT_TIMESTAMP
                FROM %s.participant
                ORDER BY id
                """.formatted(source))) {
            statement.setString(1, config.slotOnePinHash());
            statement.setString(2, config.slotTwoPinHash());
            counts.put("participant_credential", (long) statement.executeUpdate());
        }

        counts.put("relationship_score", update(connection, """
                INSERT INTO woorisai.relationship_score (
                    id, source_participant_id, target_participant_id,
                    current_score, updated_at, version
                )
                SELECT id, source_participant_id, target_participant_id,
                       current_score, updated_at, 0
                FROM %s.relationship_score
                ORDER BY id
                """.formatted(source)));
        counts.put("score_change", update(connection, """
                INSERT INTO woorisai.score_change (
                    id, relationship_score_id, changed_by_id, delta,
                    resulting_score, reason, created_at
                )
                SELECT id, relationship_score_id, changed_by_id, delta,
                       resulting_score, NULLIF(reason, ''), created_at
                FROM %s.score_change
                ORDER BY id
                """.formatted(source)));
        counts.put("score_change_comment", update(connection, """
                INSERT INTO woorisai.score_change_comment (
                    id, score_change_id, author_id, content, created_at
                )
                SELECT id, score_change_id, author_id, NULLIF(content, ''), created_at
                FROM %s.score_change_comment
                ORDER BY id
                """.formatted(source)));
        counts.put("diary_entry", update(connection, """
                INSERT INTO woorisai.diary_entry (
                    id, author_id, content, created_at, updated_at, version
                )
                SELECT id, author_id, content, created_at, updated_at, 0
                FROM %s.diary_entry
                ORDER BY id
                """.formatted(source)));
        counts.put("diary_entry_comment", update(connection, """
                INSERT INTO woorisai.diary_entry_comment (
                    id, diary_entry_id, author_id, content,
                    created_at, updated_at, version
                )
                SELECT id, diary_entry_id, author_id, content, created_at, NULL, 0
                FROM %s.diary_entry_comment
                ORDER BY id
                """.formatted(source)));
        counts.put("media_attachment", update(connection, """
                INSERT INTO woorisai.media_attachment (
                    id, uploader_id, score_change_id, score_change_comment_id,
                    diary_entry_id, purpose, kind, status, object_key,
                    original_name, content_type, expected_size, actual_size,
                    position, created_at, ready_at
                )
                SELECT id,
                       uploader_id,
                       CASE WHEN purpose = 'score_change' THEN score_change_id END,
                       CASE WHEN purpose = 'comment' THEN comment_id END,
                       CASE WHEN purpose = 'diary_entry' THEN diary_entry_id END,
                       CASE purpose
                         WHEN 'score_change' THEN 'SCORE_CHANGE'
                         WHEN 'comment' THEN 'SCORE_CHANGE_COMMENT'
                         WHEN 'diary_entry' THEN 'DIARY_ENTRY'
                       END,
                       upper(kind),
                       'READY',
                       object_key,
                       original_name,
                       content_type,
                       expected_size,
                       actual_size,
                       position,
                       created_at,
                       finalized_at
                FROM %s.media_attachment
                WHERE status = 'attached'
                ORDER BY id
                """.formatted(source)));
        return Map.copyOf(counts);
    }

    private void validateCopiedData(
            Connection connection,
            CutoverConfig config,
            Map<String, Long> counts) throws SQLException {
        String source = quoted(config.sourceSchema());
        Map<String, String> sourceCountTables = Map.of(
                "participant", "participant",
                "relationship_score", "relationship_score",
                "score_change", "score_change",
                "score_change_comment", "score_change_comment",
                "diary_entry", "diary_entry",
                "diary_entry_comment", "diary_entry_comment");
        for (Map.Entry<String, String> table : sourceCountTables.entrySet()) {
            long sourceCount = queryLong(
                    connection,
                    "SELECT COUNT(*) FROM " + source + "." + quoted(table.getValue()));
            long targetCount = queryLong(
                    connection,
                    "SELECT COUNT(*) FROM woorisai." + quoted(table.getKey()));
            if (sourceCount != targetCount || targetCount != counts.get(table.getKey())) {
                throw new CutoverException("A copied business table row count does not match source");
            }
            assertZero(
                    connection,
                    "A copied business table identifier set does not match source",
                    """
                    SELECT id FROM %1$s.%2$s
                    EXCEPT SELECT id FROM woorisai.%2$s
                    UNION ALL
                    SELECT id FROM woorisai.%2$s
                    EXCEPT SELECT id FROM %1$s.%2$s
                    """.formatted(source, quoted(table.getKey())));
        }
        long attachedSourceCount = queryLong(
                connection,
                "SELECT COUNT(*) FROM " + source + ".media_attachment WHERE status = 'attached'");
        long targetMediaCount = queryLong(
                connection,
                "SELECT COUNT(*) FROM woorisai.media_attachment");
        if (attachedSourceCount != targetMediaCount
                || targetMediaCount != counts.get("media_attachment")) {
            throw new CutoverException("The attached media row count does not match source");
        }
        assertZero(
                connection,
                "The copied attached media identifier set does not match source",
                """
                SELECT id FROM %1$s.media_attachment WHERE status = 'attached'
                EXCEPT SELECT id FROM woorisai.media_attachment
                UNION ALL
                SELECT id FROM woorisai.media_attachment
                EXCEPT SELECT id FROM %1$s.media_attachment WHERE status = 'attached'
                """.formatted(source));
        assertEquals(
                connection,
                "The copied credentials must contain exactly the canonical pair",
                2,
                "SELECT COUNT(*) FROM woorisai.participant_credential");
        try (PreparedStatement statement = connection.prepareStatement("""
                SELECT COUNT(*)
                FROM woorisai.participant participant
                JOIN woorisai.participant_credential credential
                  ON credential.participant_id = participant.id
                WHERE (participant.slot = 1 AND credential.pin_hash = ?)
                   OR (participant.slot = 2 AND credential.pin_hash = ?)
                """)) {
            statement.setString(1, config.slotOnePinHash());
            statement.setString(2, config.slotTwoPinHash());
            try (ResultSet result = statement.executeQuery()) {
                if (!result.next() || result.getLong(1) != 2) {
                    throw new CutoverException(
                            "The copied credentials do not match their participant slots");
                }
            }
        }
        assertEquals(
                connection,
                "Copied optimistic versions must all be zero",
                0,
                """
                SELECT COUNT(*) FROM (
                    SELECT version FROM woorisai.relationship_score
                    UNION ALL SELECT version FROM woorisai.diary_entry
                    UNION ALL SELECT version FROM woorisai.diary_entry_comment
                ) versions
                WHERE version <> 0
                """);
        assertZero(
                connection,
                "Copied participant fields differ from source",
                """
                SELECT source.id
                FROM %1$s.participant source
                FULL JOIN woorisai.participant target USING (id)
                WHERE source.id IS NULL OR target.id IS NULL
                   OR target.slot IS DISTINCT FROM source.slot
                   OR target.display_name IS DISTINCT FROM source.display_name
                   OR target.created_at IS DISTINCT FROM source.created_at
                """.formatted(source));
        assertZero(
                connection,
                "Copied relationship fields differ from source",
                """
                SELECT source.id
                FROM %1$s.relationship_score source
                FULL JOIN woorisai.relationship_score target USING (id)
                WHERE source.id IS NULL OR target.id IS NULL
                   OR target.source_participant_id IS DISTINCT FROM source.source_participant_id
                   OR target.target_participant_id IS DISTINCT FROM source.target_participant_id
                   OR target.current_score IS DISTINCT FROM source.current_score
                   OR target.updated_at IS DISTINCT FROM source.updated_at
                   OR target.version <> 0
                """.formatted(source));
        assertZero(
                connection,
                "Copied score history fields differ from source",
                """
                SELECT source.id
                FROM %1$s.score_change source
                FULL JOIN woorisai.score_change target USING (id)
                WHERE source.id IS NULL OR target.id IS NULL
                   OR target.relationship_score_id IS DISTINCT FROM source.relationship_score_id
                   OR target.changed_by_id IS DISTINCT FROM source.changed_by_id
                   OR target.delta IS DISTINCT FROM source.delta
                   OR target.resulting_score IS DISTINCT FROM source.resulting_score
                   OR target.reason IS DISTINCT FROM NULLIF(source.reason, '')
                   OR target.created_at IS DISTINCT FROM source.created_at
                """.formatted(source));
        assertZero(
                connection,
                "Copied comment authors or fields differ from source",
                """
                SELECT source.id
                FROM %1$s.score_change_comment source
                FULL JOIN woorisai.score_change_comment target USING (id)
                WHERE source.id IS NULL OR target.id IS NULL
                   OR target.score_change_id IS DISTINCT FROM source.score_change_id
                   OR target.author_id IS DISTINCT FROM source.author_id
                   OR target.content IS DISTINCT FROM NULLIF(source.content, '')
                   OR target.created_at IS DISTINCT FROM source.created_at
                UNION ALL
                SELECT source.id
                FROM %1$s.diary_entry_comment source
                FULL JOIN woorisai.diary_entry_comment target USING (id)
                WHERE source.id IS NULL OR target.id IS NULL
                   OR target.diary_entry_id IS DISTINCT FROM source.diary_entry_id
                   OR target.author_id IS DISTINCT FROM source.author_id
                   OR target.content IS DISTINCT FROM source.content
                   OR target.created_at IS DISTINCT FROM source.created_at
                   OR target.updated_at IS NOT NULL
                   OR target.version <> 0
                """.formatted(source));
        assertZero(
                connection,
                "Copied diary fields differ from source",
                """
                SELECT source.id
                FROM %1$s.diary_entry source
                FULL JOIN woorisai.diary_entry target USING (id)
                WHERE source.id IS NULL OR target.id IS NULL
                   OR target.author_id IS DISTINCT FROM source.author_id
                   OR target.content IS DISTINCT FROM source.content
                   OR target.created_at IS DISTINCT FROM source.created_at
                   OR target.updated_at IS DISTINCT FROM source.updated_at
                   OR target.version <> 0
                """.formatted(source));
        assertZero(
                connection,
                "Copied attached media fields differ from source mapping",
                """
                SELECT source.id
                FROM %1$s.media_attachment source
                FULL JOIN woorisai.media_attachment target
                  ON target.id = source.id AND source.status = 'attached'
                WHERE source.status = 'attached'
                  AND (
                    target.id IS NULL
                    OR target.uploader_id IS DISTINCT FROM source.uploader_id
                    OR target.score_change_id IS DISTINCT FROM
                       CASE WHEN source.purpose = 'score_change' THEN source.score_change_id END
                    OR target.score_change_comment_id IS DISTINCT FROM
                       CASE WHEN source.purpose = 'comment' THEN source.comment_id END
                    OR target.diary_entry_id IS DISTINCT FROM
                       CASE WHEN source.purpose = 'diary_entry' THEN source.diary_entry_id END
                    OR target.purpose IS DISTINCT FROM CASE source.purpose
                         WHEN 'score_change' THEN 'SCORE_CHANGE'
                         WHEN 'comment' THEN 'SCORE_CHANGE_COMMENT'
                         WHEN 'diary_entry' THEN 'DIARY_ENTRY' END
                    OR target.kind IS DISTINCT FROM upper(source.kind)
                    OR target.status <> 'READY'
                    OR target.object_key IS DISTINCT FROM source.object_key
                    OR target.original_name IS DISTINCT FROM source.original_name
                    OR target.content_type IS DISTINCT FROM source.content_type
                    OR target.expected_size IS DISTINCT FROM source.expected_size
                    OR target.actual_size IS DISTINCT FROM source.actual_size
                    OR target.position IS DISTINCT FROM source.position
                    OR target.created_at IS DISTINCT FROM source.created_at
                    OR target.ready_at IS DISTINCT FROM source.finalized_at
                  )
                """.formatted(source));
        assertEquals(
                connection,
                "Notification and event publication tables must remain empty",
                0,
                """
                SELECT (SELECT COUNT(*) FROM woorisai.notification_fid)
                     + (SELECT COUNT(*) FROM woorisai.event_publication)
                """);
    }

    private void resetIdentitySequences(Connection connection) throws SQLException {
        for (String table : IDENTITY_TABLES) {
            long maximum = queryLong(
                    connection,
                    "SELECT COALESCE(MAX(id), 0) FROM woorisai." + quoted(table));
            String sequence = resolveSequence(connection, table);
            String[] names = sequence.split("\\.", 2);
            execute(
                    connection,
                    "ALTER SEQUENCE " + quoted(names[0]) + "." + quoted(names[1])
                            + " RESTART WITH " + Math.addExact(maximum, 1));
        }
    }

    private void validateSequences(Connection connection) throws SQLException {
        for (String table : IDENTITY_TABLES) {
            long maximum = queryLong(
                    connection,
                    "SELECT COALESCE(MAX(id), 0) FROM woorisai." + quoted(table));
            String sequence = resolveSequence(connection, table);
            String[] names = sequence.split("\\.", 2);
            try (Statement statement = connection.createStatement();
                    ResultSet result = statement.executeQuery(
                            "SELECT last_value, is_called FROM "
                                    + quoted(names[0]) + "." + quoted(names[1]))) {
                if (!result.next()) {
                    throw new CutoverException("A target identity sequence state is unavailable");
                }
                long expectedValue = Math.addExact(maximum, 1);
                if (result.getLong(1) != expectedValue || result.getBoolean(2)) {
                    throw new CutoverException("A target identity sequence was not reset safely");
                }
            }
        }
    }

    private String resolveSequence(Connection connection, String table) throws SQLException {
        String sequence = queryString(
                connection,
                "SELECT pg_get_serial_sequence('woorisai." + table + "', 'id')");
        if (sequence == null || !sequence.matches("[a-z_][a-z0-9_]*\\.[a-z_][a-z0-9_]*")) {
            throw new CutoverException("A target identity sequence could not be resolved");
        }
        return sequence;
    }

    private void lockTables(
            Connection connection,
            String schema,
            List<String> tables,
            String mode) throws SQLException {
        String names = tables.stream()
                .map(table -> quoted(schema) + "." + quoted(table))
                .reduce((left, right) -> left + ", " + right)
                .orElseThrow();
        execute(connection, "LOCK TABLE " + names + " IN " + mode + " MODE");
    }

    private static long update(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement()) {
            return statement.executeUpdate(sql);
        }
    }

    private static void execute(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement()) {
            statement.execute(sql);
        }
    }

    private static void assertZero(
            Connection connection,
            String message,
            String sql) throws SQLException {
        if (queryLong(connection, "SELECT COUNT(*) FROM (" + sql + ") violations") != 0) {
            throw new CutoverException(message);
        }
    }

    private static void assertEquals(
            Connection connection,
            String message,
            long expected,
            String sql) throws SQLException {
        if (queryLong(connection, sql) != expected) {
            throw new CutoverException(message);
        }
    }

    private static long queryLong(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement();
                ResultSet result = statement.executeQuery(sql)) {
            if (!result.next()) {
                throw new CutoverException("A required validation query returned no result");
            }
            return result.getLong(1);
        }
    }

    private static String queryString(Connection connection, String sql) throws SQLException {
        try (Statement statement = connection.createStatement();
                ResultSet result = statement.executeQuery(sql)) {
            return result.next() ? result.getString(1) : null;
        }
    }

    private static Set<String> stringSet(Connection connection, String sql, String... values)
            throws SQLException {
        Set<String> result = new LinkedHashSet<>();
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            for (int index = 0; index < values.length; index++) {
                statement.setString(index + 1, values[index]);
            }
            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    result.add(rows.getString(1));
                }
            }
        }
        return Set.copyOf(result);
    }

    private static String quoted(String identifier) {
        if (!identifier.matches("[a-z_][a-z0-9_]*")) {
            throw new CutoverException("A database identifier is invalid");
        }
        return '"' + identifier + '"';
    }

    private static void rollback(Connection connection, Throwable failure) {
        try {
            connection.rollback();
        } catch (SQLException rollbackFailure) {
            failure.addSuppressed(rollbackFailure);
        }
    }

    @SafeVarargs
    private static Map<String, Set<String>> orderedColumns(Map.Entry<String, Set<String>>... entries) {
        Map<String, Set<String>> result = new LinkedHashMap<>();
        for (Map.Entry<String, Set<String>> entry : entries) {
            result.put(entry.getKey(), entry.getValue());
        }
        return Map.copyOf(result);
    }

    private static Map.Entry<String, Set<String>> entry(String table, String... columns) {
        return Map.entry(table, Set.of(columns));
    }
}

record DataCopyReport(boolean committed, Map<String, Long> rowCounts) {

    DataCopyReport {
        rowCounts = Map.copyOf(rowCounts);
    }
}
