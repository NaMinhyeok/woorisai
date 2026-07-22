package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.media.MediaKind;
import org.junit.jupiter.api.Test;

class MediaPolicyTest {

    private final MediaPolicy policy = new MediaPolicy(900);

    @Test
    void acceptsAParentFreeCommentImageAndNormalizesClientMetadata() {
        var requested = policy.validate(
                42L,
                MediaPurpose.SCORE_CHANGE_COMMENT,
                MediaKind.IMAGE,
                "  folder\\photo.PNG  ",
                " IMAGE/PNG; charset=binary ",
                1024);

        assertThat(requested.uploaderId()).isEqualTo(42L);
        assertThat(requested.originalName()).isEqualTo("photo.PNG");
        assertThat(requested.contentType()).isEqualTo("image/png");
        assertThat(requested.expectedSize()).isEqualTo(1024L);
    }

    @Test
    void acceptsCanonicalJpegAndRejectsTheNonCanonicalJpgAlias() {
        var requested = policy.validate(
                42L,
                MediaPurpose.DIARY_ENTRY,
                MediaKind.IMAGE,
                "photo.jpg",
                " IMAGE/JPEG; charset=binary ",
                1024);

        assertThat(requested.contentType()).isEqualTo("image/jpeg");
        assertThatThrownBy(() -> policy.validate(
                        42L,
                        MediaPurpose.DIARY_ENTRY,
                        MediaKind.IMAGE,
                        "photo.jpg",
                        "image/jpg",
                        1024))
                .isInstanceOf(InvalidMediaUploadRequestException.class);
    }

    @Test
    void rejectsScoreVideoUnsupportedMimeAndOversizedContent() {
        assertThatThrownBy(() -> policy.validate(
                1L,
                MediaPurpose.SCORE_CHANGE,
                MediaKind.VIDEO,
                "clip.mp4",
                "video/mp4",
                1024))
                .isInstanceOf(InvalidMediaUploadRequestException.class);

        assertThatThrownBy(() -> policy.validate(
                1L,
                MediaPurpose.DIARY_ENTRY,
                MediaKind.IMAGE,
                "photo.gif",
                "image/gif",
                1024))
                .isInstanceOf(InvalidMediaUploadRequestException.class);

        assertThatThrownBy(() -> policy.validate(
                1L,
                MediaPurpose.DIARY_ENTRY,
                MediaKind.IMAGE,
                "photo.png",
                "image/png",
                MediaPolicy.MAX_IMAGE_SIZE + 1))
                .isInstanceOf(InvalidMediaUploadRequestException.class);
    }

    @Test
    void rejectsIsoControlCharactersInOriginalNames() {
        assertThatThrownBy(() -> policy.validate(
                        1L,
                        MediaPurpose.DIARY_ENTRY,
                        MediaKind.IMAGE,
                        "photo\u0085.png",
                        "image/png",
                        1024))
                .isInstanceOf(InvalidMediaUploadRequestException.class);
    }
}
