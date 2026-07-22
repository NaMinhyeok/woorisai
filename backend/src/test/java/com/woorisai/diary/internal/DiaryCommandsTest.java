package com.woorisai.diary.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class DiaryCommandsTest {

    private static final UUID FIRST_UPLOAD =
            UUID.fromString("11111111-1111-4111-8111-111111111111");
    private static final UUID SECOND_UPLOAD =
            UUID.fromString("22222222-2222-4222-8222-222222222222");
    private static final UUID THIRD_UPLOAD =
            UUID.fromString("33333333-3333-4333-8333-333333333333");
    private static final UUID FOURTH_UPLOAD =
            UUID.fromString("44444444-4444-4444-8444-444444444444");
    private static final UUID FIFTH_UPLOAD =
            UUID.fromString("55555555-5555-4555-8555-555555555555");

    @Test
    void createEntryNormalizesContentAndTreatsMissingMediaAsEmpty() {
        CreateDiaryEntryCommand command = CreateDiaryEntryCommand.from(
                "\t 함께 남길 기록 \u3000", null);

        assertThat(command.content().value()).isEqualTo("함께 남길 기록");
        assertThat(command.mediaUploadIds().values()).isEmpty();
    }

    @Test
    void updateEntryDistinguishesPreserveClearAndReplace() {
        UpdateDiaryEntryCommand contentOnly =
                UpdateDiaryEntryCommand.from(" changed ", null);
        UpdateDiaryEntryCommand clearMedia =
                UpdateDiaryEntryCommand.from(null, List.of());
        UpdateDiaryEntryCommand replaceBoth =
                UpdateDiaryEntryCommand.from(" changed ", List.of(FIRST_UPLOAD));

        assertThat(contentOnly.content()).hasValue(new DiaryEntryContent("changed"));
        assertThat(contentOnly.mediaUploadIds()).isEmpty();
        assertThat(clearMedia.content()).isEmpty();
        assertThat(clearMedia.mediaUploadIds())
                .hasValue(new DiaryMediaUploadIds(List.of()));
        assertThat(replaceBoth.content()).hasValue(new DiaryEntryContent("changed"));
        assertThat(replaceBoth.mediaUploadIds())
                .hasValue(new DiaryMediaUploadIds(List.of(FIRST_UPLOAD)));
        assertThatThrownBy(() -> UpdateDiaryEntryCommand.from(null, null))
                .isInstanceOf(InvalidDiaryRequestException.class);
    }

    @Test
    void mediaSelectionPreservesOrderAndRejectsInvalidCardinalityOrIdentity() {
        ArrayList<UUID> requested = new ArrayList<>(List.of(SECOND_UPLOAD, FIRST_UPLOAD));
        DiaryMediaUploadIds media = DiaryMediaUploadIds.from(requested);
        requested.clear();

        assertThat(media.values()).containsExactly(SECOND_UPLOAD, FIRST_UPLOAD);
        assertThatThrownBy(() -> DiaryMediaUploadIds.from(List.of(
                        FIRST_UPLOAD,
                        SECOND_UPLOAD,
                        THIRD_UPLOAD,
                        FOURTH_UPLOAD,
                        FIFTH_UPLOAD)))
                .isInstanceOf(InvalidDiaryRequestException.class);
        assertThatThrownBy(() -> DiaryMediaUploadIds.from(
                        List.of(FIRST_UPLOAD, FIRST_UPLOAD)))
                .isInstanceOf(InvalidDiaryRequestException.class);
        assertThatThrownBy(() -> {
                    ArrayList<UUID> withNull = new ArrayList<>();
                    withNull.add(null);
                    DiaryMediaUploadIds.from(withNull);
                })
                .isInstanceOf(InvalidDiaryRequestException.class);
    }

    @Test
    void commentCommandsUseTheCommentSpecificContentLimit() {
        assertThat(CreateDiaryCommentCommand.from(" comment ").content().value())
                .isEqualTo("comment");
        String maximum = UpdateDiaryCommentCommand.from("🙂".repeat(500))
                .content()
                .value();
        assertThat(maximum.codePointCount(0, maximum.length())).isEqualTo(500);
        assertThatThrownBy(() -> CreateDiaryCommentCommand.from("🙂".repeat(501)))
                .isInstanceOf(InvalidDiaryRequestException.class);
    }
}
