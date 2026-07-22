package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThat;

import com.woorisai.media.MediaKind;
import java.util.List;
import org.junit.jupiter.api.Test;

class MediaAttachmentGroupPolicyTest {

    @Test
    void scoreGroupsAllowAtMostOneImage() {
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.SCORE, List.of()))
                .isTrue();
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.SCORE,
                        List.of(MediaKind.IMAGE)))
                .isTrue();
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.SCORE,
                        List.of(MediaKind.VIDEO)))
                .isFalse();
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.SCORE,
                        List.of(MediaKind.IMAGE, MediaKind.IMAGE)))
                .isFalse();
    }

    @Test
    void flexibleGroupsAllowFourImagesOrOneVideoWithoutMixing() {
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.FLEXIBLE,
                        List.of(MediaKind.IMAGE, MediaKind.IMAGE, MediaKind.IMAGE, MediaKind.IMAGE)))
                .isTrue();
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.FLEXIBLE,
                        List.of(MediaKind.VIDEO)))
                .isTrue();
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.FLEXIBLE,
                        List.of(MediaKind.IMAGE, MediaKind.VIDEO)))
                .isFalse();
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.FLEXIBLE,
                        List.of(
                                MediaKind.IMAGE,
                                MediaKind.IMAGE,
                                MediaKind.IMAGE,
                                MediaKind.IMAGE,
                                MediaKind.IMAGE)))
                .isFalse();
    }
}
