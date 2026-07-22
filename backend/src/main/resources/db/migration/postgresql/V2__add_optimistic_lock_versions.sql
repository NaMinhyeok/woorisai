ALTER TABLE woorisai.relationship_score
    ADD COLUMN version BIGINT NOT NULL DEFAULT 0;

ALTER TABLE woorisai.diary_entry
    ADD COLUMN version BIGINT NOT NULL DEFAULT 0;

ALTER TABLE woorisai.diary_entry_comment
    ADD COLUMN version BIGINT NOT NULL DEFAULT 0;
