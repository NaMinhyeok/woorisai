package com.woorisai.media;

import java.util.List;
import java.util.Map;

public interface AttachedMediaQuery {

    Map<Long, List<AttachedMedia>> attachmentsForScoreChanges(
            List<ScoreChangeMediaParent> scoreChanges);

    Map<Long, List<AttachedMedia>> attachmentsForScoreComments(
            List<ScoreCommentMediaParent> scoreComments);

    Map<Long, List<AttachedMedia>> attachmentsForDiaryEntries(
            List<DiaryEntryMediaParent> diaryEntries);

    final class InvalidAttachedMediaQueryException extends RuntimeException {

        public InvalidAttachedMediaQueryException() {
            super("Attached media parent descriptors are invalid");
        }
    }

    final class AttachedMediaUnavailableException extends RuntimeException {

        public AttachedMediaUnavailableException(Throwable cause) {
            super("Attached media is not available", cause);
        }
    }
}
