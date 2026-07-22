package com.woorisai.diary;

public record DiaryEntryCommentCreated(
        long recipientParticipantId,
        long diaryEntryId) {

    public DiaryEntryCommentCreated {
        if (recipientParticipantId <= 0 || diaryEntryId <= 0) {
            throw new IllegalArgumentException("Diary comment event identifiers must be positive");
        }
    }
}
