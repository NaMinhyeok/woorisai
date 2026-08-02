package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.media.MediaKind;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

class MediaAttachmentTest {

    private static final long UPLOADER_ID = 4_000_000_001L;
    private static final long PARENT_ID = 77L;
    private static final Instant CREATED_AT = Instant.parse("2026-07-21T00:00:00Z");
    private static final Instant READY_AT = Instant.parse("2026-07-21T00:00:01Z");

    @Nested
    class APurposeAcceptsOnlyItsOwnParent {

        @ParameterizedTest
        @EnumSource(MediaPurpose.class)
        void byRejectingEveryOtherParentKind(MediaPurpose purpose) {
            for (MediaPurpose attempted : MediaPurpose.values()) {
                MediaAttachment media = ready(purpose);

                if (attempted == purpose) {
                    assertThatCode(() -> attach(media, attempted))
                            .as("%s accepts its own parent", purpose)
                            .doesNotThrowAnyException();
                    continue;
                }
                assertThatThrownBy(() -> attach(media, attempted))
                        .as("%s must not accept a %s parent", purpose, attempted)
                        .isInstanceOf(IllegalStateException.class);
            }
        }

        // A parent the purpose does not allow would leave a row that no read can ever return:
        // isParentedReady() answers false for it, so the attachment is stored yet invisible.
        @ParameterizedTest
        @EnumSource(MediaPurpose.class)
        void soAnAttachedMediaIsAlwaysReadable(MediaPurpose purpose) {
            MediaAttachment media = ready(purpose);

            attach(media, purpose);

            assertThatCode(() -> {
                if (!media.isParentedReady()) {
                    throw new AssertionError(purpose + " attached to an unreadable state");
                }
            }).doesNotThrowAnyException();
        }
    }

    @Test
    void aPendingUploadCannotBeAttachedBeforeItIsReady() {
        MediaAttachment pending = pending(MediaPurpose.DIARY_ENTRY);

        assertThatThrownBy(() -> pending.attachDiaryEntry(PARENT_ID, (short) 0))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void anAttachedMediaCannotBeReattachedWithoutDetaching() {
        MediaAttachment media = ready(MediaPurpose.DIARY_ENTRY);
        media.attachDiaryEntry(PARENT_ID, (short) 0);

        assertThatThrownBy(() -> media.attachDiaryEntry(PARENT_ID + 1, (short) 0))
                .isInstanceOf(IllegalStateException.class);
    }

    private static void attach(MediaAttachment media, MediaPurpose parent) {
        switch (parent) {
            case SCORE_CHANGE -> media.attachScoreChange(PARENT_ID);
            case SCORE_CHANGE_COMMENT -> media.attachScoreComment(PARENT_ID, (short) 0);
            case DIARY_ENTRY -> media.attachDiaryEntry(PARENT_ID, (short) 0);
        }
    }

    private static MediaAttachment ready(MediaPurpose purpose) {
        MediaAttachment media = pending(purpose);
        media.complete("media/" + UUID.randomUUID(), 1_024L, READY_AT);
        return media;
    }

    private static MediaAttachment pending(MediaPurpose purpose) {
        return MediaAttachment.pending(
                UUID.randomUUID(),
                UPLOADER_ID,
                purpose,
                MediaKind.IMAGE,
                "pending/" + UUID.randomUUID(),
                "attachment.jpg",
                "image/jpeg",
                1_024L,
                CREATED_AT);
    }
}
