package com.woorisai.media.internal;

import com.woorisai.media.MediaKind;
import java.util.List;

final class MediaAttachmentGroupPolicy {

    enum Group {
        SCORE(1),
        FLEXIBLE(4);

        private final int maximum;

        Group(int maximum) {
            this.maximum = maximum;
        }

        int maximum() {
            return maximum;
        }
    }

    private MediaAttachmentGroupPolicy() {}

    static boolean accepts(Group group, List<MediaKind> kinds) {
        if (kinds.size() > group.maximum()) {
            return false;
        }
        if (group == Group.SCORE) {
            return kinds.stream().allMatch(kind -> kind == MediaKind.IMAGE);
        }
        boolean images = kinds.stream().allMatch(kind -> kind == MediaKind.IMAGE);
        boolean oneVideo = kinds.size() == 1 && kinds.getFirst() == MediaKind.VIDEO;
        return images || oneVideo;
    }
}
