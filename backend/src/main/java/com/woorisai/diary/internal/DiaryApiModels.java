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

// Every diary response answers the same two questions about its author: who wrote it,
// and is that the participant reading it. Resolving them together keeps the pair from
// drifting apart across the responses that carry both.
record DiaryAuthorship(DiaryParticipantResponse author, boolean isMine) {

    static DiaryAuthorship of(ParticipantReference author, ParticipantReference actor) {
        return new DiaryAuthorship(
                DiaryParticipantResponse.from(author), author.id() == actor.id());
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

    static DiaryEntryListItemResponse of(
            DiaryEntry entry,
            DiaryAuthorship authorship,
            List<DiaryMediaResponse> attachments,
            long commentCount) {
        return new DiaryEntryListItemResponse(
                entry.getId(),
                authorship.author(),
                entry.getContent(),
                entry.getCreatedAt(),
                entry.getUpdatedAt(),
                authorship.isMine(),
                attachments,
                commentCount);
    }
}

record DiaryCommentResponse(
        long id,
        DiaryParticipantResponse author,
        String content,
        Instant createdAt,
        Instant updatedAt,
        boolean isMine) {

    static DiaryCommentResponse of(DiaryEntryComment comment, DiaryAuthorship authorship) {
        return new DiaryCommentResponse(
                comment.getId(),
                authorship.author(),
                comment.getContent(),
                comment.getCreatedAt(),
                comment.getUpdatedAt(),
                authorship.isMine());
    }
}

record DiaryEntryCommentCreatedResponse(
        long id,
        DiaryParticipantResponse author,
        String content,
        Instant createdAt,
        Instant updatedAt,
        boolean isMine) {

    static DiaryEntryCommentCreatedResponse of(
            DiaryEntryComment comment, DiaryAuthorship authorship) {
        return new DiaryEntryCommentCreatedResponse(
                comment.getId(),
                authorship.author(),
                comment.getContent(),
                comment.getCreatedAt(),
                comment.getUpdatedAt(),
                authorship.isMine());
    }
}

record DiaryEntryCommentUpdatedResponse(
        long id,
        DiaryParticipantResponse author,
        String content,
        Instant createdAt,
        Instant updatedAt,
        boolean isMine) {

    static DiaryEntryCommentUpdatedResponse of(
            DiaryEntryComment comment, DiaryAuthorship authorship) {
        return new DiaryEntryCommentUpdatedResponse(
                comment.getId(),
                authorship.author(),
                comment.getContent(),
                comment.getCreatedAt(),
                comment.getUpdatedAt(),
                authorship.isMine());
    }
}

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

    static DiaryEntryCreatedResponse of(
            DiaryEntry entry,
            DiaryAuthorship authorship,
            List<DiaryMediaResponse> attachments,
            long commentCount) {
        return new DiaryEntryCreatedResponse(
                entry.getId(),
                authorship.author(),
                entry.getContent(),
                entry.getCreatedAt(),
                entry.getUpdatedAt(),
                authorship.isMine(),
                attachments,
                commentCount);
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

    static DiaryEntryDetailResponse of(
            DiaryEntry entry,
            DiaryAuthorship authorship,
            List<DiaryMediaResponse> attachments,
            List<DiaryCommentResponse> comments) {
        return new DiaryEntryDetailResponse(
                entry.getId(),
                authorship.author(),
                entry.getContent(),
                entry.getCreatedAt(),
                entry.getUpdatedAt(),
                authorship.isMine(),
                attachments,
                comments.size(),
                comments);
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

    static DiaryEntryUpdatedResponse of(
            DiaryEntry entry,
            DiaryAuthorship authorship,
            List<DiaryMediaResponse> attachments,
            long commentCount) {
        return new DiaryEntryUpdatedResponse(
                entry.getId(),
                authorship.author(),
                entry.getContent(),
                entry.getCreatedAt(),
                entry.getUpdatedAt(),
                authorship.isMine(),
                attachments,
                commentCount);
    }
}
