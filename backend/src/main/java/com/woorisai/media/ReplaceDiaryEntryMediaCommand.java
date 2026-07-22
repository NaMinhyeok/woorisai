package com.woorisai.media;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

public record ReplaceDiaryEntryMediaCommand(
        long expectedUploaderId,
        long diaryEntryId,
        List<UUID> mediaUploadIds) {

    public ReplaceDiaryEntryMediaCommand {
        if (mediaUploadIds != null) {
            mediaUploadIds = Collections.unmodifiableList(new ArrayList<>(mediaUploadIds));
        }
    }
}
