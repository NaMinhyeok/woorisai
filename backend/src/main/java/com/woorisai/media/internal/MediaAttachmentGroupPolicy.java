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
        return acceptsFlexible(kinds);
    }

    /**
     * Whether a score comment or diary entry may hold this group of kinds.
     *
     * <p>This gate runs on both writes and reads, so widening it is safe for stored data while
     * narrowing it would make existing groups unreadable. The size ceiling is already enforced by
     * {@link #accepts}, which leaves only the video count: images and video share a group freely,
     * but a second video does not join it.
     *
     * <p>One video is a size decision, not a taste one. A video is ten times an image's ceiling,
     * so a group holding one caps at roughly 130 MiB while four would reach 400 MiB — past the
     * client's preview cache budget, which would then evict a video the reader just swiped away
     * from and fetch it again on the way back. Raising this limit means raising that budget in the
     * same change.
     */
    private static boolean acceptsFlexible(List<MediaKind> kinds) {
        return kinds.stream().filter(kind -> kind == MediaKind.VIDEO).count() <= 1;
    }
}
