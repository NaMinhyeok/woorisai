ALTER TABLE woorisai.media_attachment ADD COLUMN revoked_at TIMESTAMPTZ;

UPDATE woorisai.media_attachment AS attachment
SET revoked_at = entry.deleted_at
FROM woorisai.diary_entry AS entry
WHERE attachment.diary_entry_id = entry.id AND entry.deleted_at IS NOT NULL;