package com.woorisai.diary;

public record DiaryEntryCreated(
        long recipientParticipantId,
        long diaryEntryId) {

    public DiaryEntryCreated {
        if (recipientParticipantId <= 0 || diaryEntryId <= 0) {
            throw new IllegalArgumentException("Diary entry event identifiers must be positive");
        }
    }
}
