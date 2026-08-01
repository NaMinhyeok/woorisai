-- H2 mirror of the PostgreSQL V3 migration.
-- H2 does not support partial indexes, so the two live-row indexes exist only in
-- the PostgreSQL migration. Index and concurrency semantics are proven by postgresTest.

ALTER TABLE woorisai.diary_entry
    ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE woorisai.diary_entry_comment
    ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE woorisai.score_change
    ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE woorisai.score_change_comment
    ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE woorisai.participant
    ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE woorisai.diary_entry
    ADD CONSTRAINT diary_entry_deleted_at_ck
        CHECK (deleted_at IS NULL OR deleted_at >= created_at);

ALTER TABLE woorisai.diary_entry_comment
    ADD CONSTRAINT diary_entry_comment_deleted_at_ck
        CHECK (deleted_at IS NULL OR deleted_at >= created_at);

ALTER TABLE woorisai.score_change
    ADD CONSTRAINT score_change_deleted_at_ck
        CHECK (deleted_at IS NULL OR deleted_at >= created_at);

ALTER TABLE woorisai.score_change_comment
    ADD CONSTRAINT score_change_comment_deleted_at_ck
        CHECK (deleted_at IS NULL OR deleted_at >= created_at);

ALTER TABLE woorisai.participant
    ADD CONSTRAINT participant_deleted_at_ck
        CHECK (deleted_at IS NULL OR deleted_at >= created_at);
