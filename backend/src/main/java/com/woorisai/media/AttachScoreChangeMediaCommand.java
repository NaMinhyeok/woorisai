package com.woorisai.media;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

public record AttachScoreChangeMediaCommand(
        long expectedUploaderId,
        long scoreChangeId,
        List<UUID> mediaUploadIds) {

    public AttachScoreChangeMediaCommand {
        if (mediaUploadIds != null) {
            mediaUploadIds = Collections.unmodifiableList(new ArrayList<>(mediaUploadIds));
        }
    }
}
