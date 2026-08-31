ALTER TABLE woorisai.relationship_score
    DROP CONSTRAINT relationship_score_value_ck;

ALTER TABLE woorisai.relationship_score
    ALTER COLUMN current_score BIGINT;

ALTER TABLE woorisai.relationship_score
    ADD CONSTRAINT relationship_score_value_ck CHECK (current_score >= 0);

ALTER TABLE woorisai.score_change
    DROP CONSTRAINT score_change_delta_ck;

ALTER TABLE woorisai.score_change
    DROP CONSTRAINT score_change_result_ck;

ALTER TABLE woorisai.score_change
    ALTER COLUMN delta BIGINT;

ALTER TABLE woorisai.score_change
    ALTER COLUMN resulting_score BIGINT;

ALTER TABLE woorisai.score_change
    ADD CONSTRAINT score_change_delta_ck CHECK (delta <> 0);

ALTER TABLE woorisai.score_change
    ADD CONSTRAINT score_change_result_ck CHECK (resulting_score >= 0);
