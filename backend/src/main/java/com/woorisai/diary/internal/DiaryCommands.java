package com.woorisai.diary.internal;

import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

record CreateDiaryEntryCommand(
        DiaryEntryContent content,
        DiaryMediaUploadIds mediaUploadIds) {

    static CreateDiaryEntryCommand from(String content, List<UUID> mediaUploadIds) {
        return new CreateDiaryEntryCommand(
                DiaryEntryContent.from(content),
                DiaryMediaUploadIds.fromNullable(mediaUploadIds));
    }

    CreateDiaryEntryCommand {
        if (content == null || mediaUploadIds == null) {
            throw new InvalidDiaryRequestException();
        }
    }
}

record UpdateDiaryEntryCommand(
        Optional<DiaryEntryContent> content,
        Optional<DiaryMediaUploadIds> mediaUploadIds) {

    static UpdateDiaryEntryCommand from(String content, List<UUID> mediaUploadIds) {
        if (content == null && mediaUploadIds == null) {
            throw new InvalidDiaryRequestException();
        }
        return new UpdateDiaryEntryCommand(
                Optional.ofNullable(content).map(DiaryEntryContent::from),
                Optional.ofNullable(mediaUploadIds).map(DiaryMediaUploadIds::from));
    }

    UpdateDiaryEntryCommand {
        if (content == null
                || mediaUploadIds == null
                || (content.isEmpty() && mediaUploadIds.isEmpty())) {
            throw new InvalidDiaryRequestException();
        }
    }
}

record CreateDiaryCommentCommand(DiaryCommentContent content) {

    static CreateDiaryCommentCommand from(String content) {
        return new CreateDiaryCommentCommand(DiaryCommentContent.from(content));
    }

    CreateDiaryCommentCommand {
        if (content == null) {
            throw new InvalidDiaryRequestException();
        }
    }
}

record UpdateDiaryCommentCommand(DiaryCommentContent content) {

    static UpdateDiaryCommentCommand from(String content) {
        return new UpdateDiaryCommentCommand(DiaryCommentContent.from(content));
    }

    UpdateDiaryCommentCommand {
        if (content == null) {
            throw new InvalidDiaryRequestException();
        }
    }
}

record DiaryMediaUploadIds(List<UUID> values) {

    private static final int MAXIMUM_UPLOADS = 4;

    DiaryMediaUploadIds {
        if (values == null
                || values.size() > MAXIMUM_UPLOADS
                || values.stream().anyMatch(id -> id == null)
                || new HashSet<>(values).size() != values.size()) {
            throw new InvalidDiaryRequestException();
        }
        values = List.copyOf(values);
    }

    static DiaryMediaUploadIds fromNullable(List<UUID> values) {
        return new DiaryMediaUploadIds(values == null ? List.of() : values);
    }

    static DiaryMediaUploadIds from(List<UUID> values) {
        return new DiaryMediaUploadIds(values);
    }
}
