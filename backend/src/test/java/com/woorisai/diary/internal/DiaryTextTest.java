package com.woorisai.diary.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.diary.DiaryEntryCommentCreated;
import org.junit.jupiter.api.Test;

class DiaryTextTest {

    @Test
    void stripsSurroundingWhitespaceAndCountsUnicodeCodePoints() {
        String supplementary = "🙂".repeat(1000);

        assertThat(DiaryText.required("\t" + supplementary + "\u3000", 1000))
                .isEqualTo(supplementary);
        assertThatThrownBy(() -> DiaryText.required(supplementary + "🙂", 1000))
                .isInstanceOf(InvalidDiaryRequestException.class);
        assertThatThrownBy(() -> DiaryText.required("\t\u3000", 1000))
                .isInstanceOf(InvalidDiaryRequestException.class);
    }

    @Test
    void rejectsUnpairedSurrogates() {
        assertThatThrownBy(() -> DiaryText.required("broken\ud800", 1000))
                .isInstanceOf(InvalidDiaryRequestException.class);
        assertThatThrownBy(() -> DiaryText.required("broken\udc00", 1000))
                .isInstanceOf(InvalidDiaryRequestException.class);
    }

    @Test
    void rejectsThePostgresqlUnsupportedNullCodePoint() {
        assertThatThrownBy(() -> DiaryText.required("before\u0000after", 1000))
                .isInstanceOf(InvalidDiaryRequestException.class);
    }

    @Test
    void eventRequiresPositiveIdentifiers() {
        DiaryEntryCommentCreated event = new DiaryEntryCommentCreated(1, 2);

        assertThat(event.recipientParticipantId()).isEqualTo(1);
        assertThat(event.diaryEntryId()).isEqualTo(2);
        assertThatThrownBy(() -> new DiaryEntryCommentCreated(0, 2))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new DiaryEntryCommentCreated(1, 0))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
