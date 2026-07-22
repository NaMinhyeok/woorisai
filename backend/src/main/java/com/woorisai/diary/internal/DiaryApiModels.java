package com.woorisai.diary.internal;

import com.woorisai.media.AttachedMedia;
import com.woorisai.participant.ParticipantReference;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

record CreateDiaryCommentRequest(String content) {

    CreateDiaryCommentCommand toCommand() {
        return CreateDiaryCommentCommand.from(content);
    }
}

record CreateDiaryEntryRequest(String content, List<UUID> mediaUploadIds) {

    CreateDiaryEntryRequest {
        if (mediaUploadIds != null) {
            mediaUploadIds = Collections.unmodifiableList(new ArrayList<>(mediaUploadIds));
        }
    }

    CreateDiaryEntryCommand toCommand() {
        return CreateDiaryEntryCommand.from(content, mediaUploadIds);
    }
}

record UpdateDiaryCommentRequest(String content) {

    UpdateDiaryCommentCommand toCommand() {
        return UpdateDiaryCommentCommand.from(content);
    }
}

record UpdateDiaryEntryRequest(String content, List<UUID> mediaUploadIds) {

    UpdateDiaryEntryRequest {
        if (mediaUploadIds != null) {
            mediaUploadIds = Collections.unmodifiableList(new ArrayList<>(mediaUploadIds));
        }
    }

    UpdateDiaryEntryCommand toCommand() {
        return UpdateDiaryEntryCommand.from(content, mediaUploadIds);
    }
}

record DiaryParticipantResponse(int slot, String displayName) {

    static DiaryParticipantResponse from(ParticipantReference participant) {
        return new DiaryParticipantResponse(participant.slot(), participant.displayName());
    }
}

record DiaryMediaResponse(
        UUID id,
        String kind,
        String fileName,
        String contentType,
        long byteSize) {

    static DiaryMediaResponse from(AttachedMedia media) {
        return new DiaryMediaResponse(
                media.id(),
                media.kind().name(),
                media.fileName(),
                media.contentType(),
                media.byteSize());
    }
}

record DiaryEntryListItemResponse(
        long id,
        DiaryParticipantResponse author,
        String content,
        Instant createdAt,
        Instant updatedAt,
        boolean isMine,
        List<DiaryMediaResponse> attachments,
        long commentCount) {

    DiaryEntryListItemResponse {
        attachments = List.copyOf(attachments);
    }
}

record DiaryCommentResponse(
        long id,
        DiaryParticipantResponse author,
        String content,
        Instant createdAt,
        Instant updatedAt,
        boolean isMine) {}

record DiaryEntryCommentCreatedResponse(
        long id,
        DiaryParticipantResponse author,
        String content,
        Instant createdAt,
        Instant updatedAt,
        boolean isMine) {}

record DiaryEntryCommentUpdatedResponse(
        long id,
        DiaryParticipantResponse author,
        String content,
        Instant createdAt,
        Instant updatedAt,
        boolean isMine) {}

record DiaryEntryCreatedResponse(
        long id,
        DiaryParticipantResponse author,
        String content,
        Instant createdAt,
        Instant updatedAt,
        boolean isMine,
        List<DiaryMediaResponse> attachments,
        long commentCount) {

    DiaryEntryCreatedResponse {
        attachments = List.copyOf(attachments);
    }
}

record DiaryEntryDetailResponse(
        long id,
        DiaryParticipantResponse author,
        String content,
        Instant createdAt,
        Instant updatedAt,
        boolean isMine,
        List<DiaryMediaResponse> attachments,
        long commentCount,
        List<DiaryCommentResponse> comments) {

    DiaryEntryDetailResponse {
        attachments = List.copyOf(attachments);
        comments = List.copyOf(comments);
    }
}

record DiaryEntryListResponse(
        List<DiaryEntryListItemResponse> results,
        int pageNumber,
        int pageSize,
        boolean hasNext,
        long totalCount) {

    DiaryEntryListResponse {
        results = List.copyOf(results);
    }
}

record DiaryEntryUpdatedResponse(
        long id,
        DiaryParticipantResponse author,
        String content,
        Instant createdAt,
        Instant updatedAt,
        boolean isMine,
        List<DiaryMediaResponse> attachments,
        long commentCount) {

    DiaryEntryUpdatedResponse {
        attachments = List.copyOf(attachments);
    }
}
