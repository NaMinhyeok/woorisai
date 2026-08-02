package com.woorisai.diary.internal;

import static com.woorisai.diary.internal.DiaryRevisions.requireRevision;

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

final class DiaryRevisions {

    private DiaryRevisions() {}

    // Only the author revises, and revising stamps updatedAt. The published *UpdatedResponse
    // schemas encode both as isMine: true and a non-nullable updatedAt.
    static void requireRevision(Instant updatedAt, boolean isMine) {
        if (updatedAt == null || !isMine) {
            throw new IllegalArgumentException("Revised diary response is invalid");
        }
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

// The read shape shared by the list, create and detail responses. `DiaryEntryResponse` is one
// published schema serving all three, so one record serves them here too.
record DiaryEntryResponse(
        long id,
        DiaryParticipantResponse author,
        String content,
        Instant createdAt,
        Instant updatedAt,
        boolean isMine,
        List<DiaryMediaResponse> attachments,
        long commentCount) {

    DiaryEntryResponse {
        attachments = List.copyOf(attachments);
    }

    static DiaryEntryResponse of(
            DiaryEntry entry,
            DiaryAuthorship authorship,
            List<DiaryMediaResponse> attachments,
            long commentCount) {
        return new DiaryEntryResponse(
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

// A revision promises more than a read: the published schema pins isMine to true and makes
// updatedAt non-nullable, because only the author revises and revising sets the timestamp.
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
        requireRevision(updatedAt, isMine);
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

record DiaryCommentUpdatedResponse(
        long id,
        DiaryParticipantResponse author,
        String content,
        Instant createdAt,
        Instant updatedAt,
        boolean isMine) {

    DiaryCommentUpdatedResponse {
        requireRevision(updatedAt, isMine);
    }

    static DiaryCommentUpdatedResponse of(
            DiaryEntryComment comment, DiaryAuthorship authorship) {
        return new DiaryCommentUpdatedResponse(
                comment.getId(),
                authorship.author(),
                comment.getContent(),
                comment.getCreatedAt(),
                comment.getUpdatedAt(),
                authorship.isMine());
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
