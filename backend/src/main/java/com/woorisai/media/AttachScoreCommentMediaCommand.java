package com.woorisai.media;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

public record AttachScoreCommentMediaCommand(
        long expectedUploaderId,
        long scoreCommentId,
        List<UUID> mediaUploadIds) {

    public AttachScoreCommentMediaCommand {
        if (mediaUploadIds != null) {
            mediaUploadIds = Collections.unmodifiableList(new ArrayList<>(mediaUploadIds));
        }
    }
}
