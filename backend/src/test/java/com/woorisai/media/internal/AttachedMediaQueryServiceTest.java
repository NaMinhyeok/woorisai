package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;

import com.woorisai.media.AttachedMediaQuery.AttachedMediaUnavailableException;
import com.woorisai.media.ScoreChangeMediaParent;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataRetrievalFailureException;

class AttachedMediaQueryServiceTest {

    private static final long UPLOADER_ID = 3_000_000_001L;

    @Test
    void mapsRepositoryFailureToThePublicQueryFailure() {
        MediaAttachmentRepository attachments = mock(MediaAttachmentRepository.class);
        var failure = new DataRetrievalFailureException("synthetic query failure");
        given(attachments
                        .findAllByPurposeAndStatusAndScoreChangeIdInOrderByScoreChangeIdAscPositionAscIdAsc(
                                MediaPurpose.SCORE_CHANGE,
                                MediaStatus.READY,
                                Set.of(20L)))
                .willThrow(failure);
        AttachedMediaQueryService service = new AttachedMediaQueryService(attachments);

        assertThatThrownBy(() -> service.attachmentsForScoreChanges(
                        List.of(new ScoreChangeMediaParent(20L, UPLOADER_ID))))
                .isInstanceOf(AttachedMediaUnavailableException.class)
                .hasCause(failure);
    }
}
