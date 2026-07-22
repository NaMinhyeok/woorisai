package com.woorisai.media.internal;

import com.woorisai.media.MediaKind;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

record InitiateMediaUploadRequest(
        @NotNull @Pattern(regexp = "scoreChange|comment|diaryEntry") String purpose,
        @NotNull @Pattern(regexp = "image|video") String kind,
        @NotBlank String fileName,
        @NotBlank @Size(max = 100) String contentType,
        @NotNull @Positive Long byteSize) {

    @AssertTrue
    boolean isPurposeCombinationValid() {
        if (purpose == null || kind == null) {
            return true;
        }
        return !"scoreChange".equals(purpose) || "image".equals(kind);
    }

    MediaPurpose mediaPurpose() {
        return switch (purpose) {
            case "scoreChange" -> MediaPurpose.SCORE_CHANGE;
            case "comment" -> MediaPurpose.SCORE_CHANGE_COMMENT;
            case "diaryEntry" -> MediaPurpose.DIARY_ENTRY;
            default -> throw new InvalidMediaUploadHttpRequestException();
        };
    }

    MediaKind mediaKind() {
        return switch (kind) {
            case "image" -> MediaKind.IMAGE;
            case "video" -> MediaKind.VIDEO;
            default -> throw new InvalidMediaUploadHttpRequestException();
        };
    }
}
