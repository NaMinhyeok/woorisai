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
    void flexibleGroupsAllowFourAttachmentsOfAnyKindMix() {
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.FLEXIBLE, List.of()))
                .isTrue();
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
                        List.of(
                                MediaKind.IMAGE,
                                MediaKind.IMAGE,
                                MediaKind.IMAGE,
                                MediaKind.IMAGE,
                                MediaKind.IMAGE)))
                .isFalse();
    }

    @Test
    void flexibleGroupsMixImagesWithOneVideoInAnyPosition() {
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.FLEXIBLE,
                        List.of(MediaKind.IMAGE, MediaKind.VIDEO)))
                .isTrue();
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.FLEXIBLE,
                        List.of(MediaKind.VIDEO, MediaKind.IMAGE)))
                .isTrue();
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.FLEXIBLE,
                        List.of(
                                MediaKind.IMAGE,
                                MediaKind.VIDEO,
                                MediaKind.IMAGE,
                                MediaKind.IMAGE)))
                .isTrue();
    }

    @Test
    void flexibleGroupsRefuseASecondVideoRegardlessOfGroupSize() {
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.FLEXIBLE,
                        List.of(MediaKind.VIDEO, MediaKind.VIDEO)))
                .isFalse();
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.FLEXIBLE,
                        List.of(
                                MediaKind.VIDEO,
                                MediaKind.IMAGE,
                                MediaKind.IMAGE,
                                MediaKind.VIDEO)))
                .isFalse();
    }

    /**
     * The gate also runs when reading stored groups, so a group that was legal when written must
     * stay readable. Every shape the previous rule accepted is asserted here on purpose.
     */
    @Test
    void groupsLegalUnderTheEarlierNoMixingRuleRemainReadable() {
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.FLEXIBLE,
                        List.of(MediaKind.IMAGE)))
                .isTrue();
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.FLEXIBLE,
                        List.of(MediaKind.IMAGE, MediaKind.IMAGE, MediaKind.IMAGE)))
                .isTrue();
        assertThat(MediaAttachmentGroupPolicy.accepts(
                        MediaAttachmentGroupPolicy.Group.SCORE, List.of(MediaKind.IMAGE)))
                .isTrue();
    }
}
