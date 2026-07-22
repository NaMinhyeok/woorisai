package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;

import com.woorisai.media.AttachScoreChangeMediaCommand;
import com.woorisai.media.AttachScoreCommentMediaCommand;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentUnavailableException;
import com.woorisai.media.MediaKind;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;

class MediaAttachmentMutationServiceTest {

    private static final long UPLOADER_ID = 3_000_000_001L;
    private static final Instant NOW = Instant.parse("2026-07-21T00:00:00Z");

    @Test
    void mapsScoreChangeFlushFailureToTheModuleFailure() {
        UUID uploadId = UUID.fromString("10000000-0000-4000-8000-000000000001");
        MediaAttachmentRepository attachments = failingFlushRepository(
                ready(uploadId, MediaPurpose.SCORE_CHANGE));
        MediaAttachmentMutationService service = new MediaAttachmentMutationService(attachments);

        assertThatThrownBy(() -> service.attachScoreChange(
                        new AttachScoreChangeMediaCommand(
                                UPLOADER_ID, 20L, List.of(uploadId))))
                .isInstanceOf(MediaAttachmentUnavailableException.class)
                .hasCauseInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void mapsScoreCommentFlushFailureToTheModuleFailure() {
        UUID uploadId = UUID.fromString("10000000-0000-4000-8000-000000000002");
        MediaAttachmentRepository attachments = failingFlushRepository(
                ready(uploadId, MediaPurpose.SCORE_CHANGE_COMMENT));
        MediaAttachmentMutationService service = new MediaAttachmentMutationService(attachments);

        assertThatThrownBy(() -> service.attachScoreComment(
                        new AttachScoreCommentMediaCommand(
                                UPLOADER_ID, 30L, List.of(uploadId))))
                .isInstanceOf(MediaAttachmentUnavailableException.class)
                .hasCauseInstanceOf(DataIntegrityViolationException.class);
    }

    private static MediaAttachmentRepository failingFlushRepository(
            MediaAttachment attachment) {
        MediaAttachmentRepository attachments = mock(MediaAttachmentRepository.class);
        given(attachments.findAllByIdForUpdate(List.of(attachment.getId())))
                .willReturn(List.of(attachment));
        doThrow(new DataIntegrityViolationException("synthetic flush failure"))
                .when(attachments)
                .flush();
        return attachments;
    }

    private static MediaAttachment ready(UUID id, MediaPurpose purpose) {
        MediaAttachment attachment = MediaAttachment.pending(
                id,
                UPLOADER_ID,
                purpose,
                MediaKind.IMAGE,
                "pending/" + id,
                "fixture.png",
                "image/png",
                8,
                NOW);
        attachment.complete("media/" + id, 8, NOW);
        return attachment;
    }
}
