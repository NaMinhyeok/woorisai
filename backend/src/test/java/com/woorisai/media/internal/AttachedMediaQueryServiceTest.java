package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;

import com.woorisai.media.AttachedMedia;
import com.woorisai.media.AttachedMediaQuery.AttachedMediaUnavailableException;
import com.woorisai.media.DiaryEntryMediaParent;
import com.woorisai.media.MediaKind;
import com.woorisai.media.ScoreChangeMediaParent;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataRetrievalFailureException;

class AttachedMediaQueryServiceTest {

    private static final long UPLOADER_ID = 3_000_000_001L;
    private static final long OTHER_UPLOADER_ID = 3_000_000_002L;
    private static final long DIARY_ENTRY_ID = 20L;
    private static final long SCORE_CHANGE_ID = 20L;

    private final MediaAttachmentRepository attachments = mock(MediaAttachmentRepository.class);
    private final AttachedMediaQueryService service = new AttachedMediaQueryService(attachments);

    @Test
    void mapsRepositoryFailureToThePublicQueryFailure() {
        var failure = new DataRetrievalFailureException("synthetic query failure");
        given(attachments.findAllByScoreChangeIdIn(anyCollection())).willThrow(failure);

        assertThatThrownBy(() -> service.attachmentsForScoreChanges(
                        List.of(new ScoreChangeMediaParent(SCORE_CHANGE_ID, UPLOADER_ID))))
                .isInstanceOf(AttachedMediaUnavailableException.class)
                .hasCause(failure);
    }

    @Nested
    class AttachmentOrder {

        @Test
        void returnsMediaInPositionOrderRegardlessOfRowOrder() {
            given(attachments.findAllByDiaryEntryIdIn(anyCollection()))
                    .willReturn(List.of(
                            diaryMedia("last.jpg", (short) 2),
                            diaryMedia("first.jpg", (short) 0),
                            diaryMedia("middle.jpg", (short) 1)));

            Map<Long, List<AttachedMedia>> found = service.attachmentsForDiaryEntries(
                    List.of(new DiaryEntryMediaParent(DIARY_ENTRY_ID, UPLOADER_ID)));

            assertThat(found.get(DIARY_ENTRY_ID))
                    .extracting(AttachedMedia::fileName)
                    .containsExactly("first.jpg", "middle.jpg", "last.jpg");
        }
    }

    @Nested
    class RejectedRows {

        @Test
        void reportsAGapInThePositionSequence() {
            given(attachments.findAllByDiaryEntryIdIn(anyCollection()))
                    .willReturn(List.of(
                            diaryMedia("first.jpg", (short) 0),
                            diaryMedia("third.jpg", (short) 2)));

            assertThatThrownBy(() -> service.attachmentsForDiaryEntries(
                            List.of(new DiaryEntryMediaParent(DIARY_ENTRY_ID, UPLOADER_ID))))
                    .isInstanceOf(AttachedMediaUnavailableException.class);
        }

        @Test
        void reportsMediaUploadedBySomeoneOtherThanTheExpectedUploader() {
            MediaAttachment foreign = MediaAttachmentFixture.readyDiaryEntry(
                    DIARY_ENTRY_ID, OTHER_UPLOADER_ID, "foreign.jpg", (short) 0);
            given(attachments.findAllByDiaryEntryIdIn(anyCollection()))
                    .willReturn(List.of(foreign));

            assertThatThrownBy(() -> service.attachmentsForDiaryEntries(
                            List.of(new DiaryEntryMediaParent(DIARY_ENTRY_ID, UPLOADER_ID))))
                    .isInstanceOf(AttachedMediaUnavailableException.class);
        }
    }

    private static MediaAttachment diaryMedia(String originalName, short position) {
        return MediaAttachmentFixture.readyDiaryEntry(
                DIARY_ENTRY_ID, UPLOADER_ID, originalName, position);
    }

    private static final class MediaAttachmentFixture {

        private static MediaAttachment readyDiaryEntry(
                long diaryEntryId, long uploaderId, String originalName, short position) {
            MediaAttachment attachment = pending(uploaderId, originalName);
            attachment.complete("diary/" + UUID.randomUUID(), 1_024L, Instant.EPOCH);
            attachment.attachDiaryEntry(diaryEntryId, position);
            return attachment;
        }

        private static MediaAttachment pending(long uploaderId, String originalName) {
            return MediaAttachment.pending(
                    UUID.randomUUID(),
                    uploaderId,
                    MediaPurpose.DIARY_ENTRY,
                    MediaKind.IMAGE,
                    "diary/pending/" + UUID.randomUUID(),
                    originalName,
                    "image/jpeg",
                    1_024L,
                    Instant.EPOCH);
        }
    }
}
