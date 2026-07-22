package com.woorisai.relationship.internal;

import com.woorisai.media.AttachedMedia;
import com.woorisai.participant.ParticipantReference;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

record ChangeScoreRequest(
        Integer delta,
        Integer targetScore,
        String reason,
        List<UUID> mediaUploadIds) {

    ChangeScoreRequest {
        if (mediaUploadIds != null) {
            mediaUploadIds = Collections.unmodifiableList(new ArrayList<>(mediaUploadIds));
        }
    }

    ChangeScoreCommand toCommand() {
        return ChangeScoreCommand.from(delta, targetScore, reason, mediaUploadIds);
    }
}

record CreateScoreChangeCommentRequest(String content, List<UUID> mediaUploadIds) {

    CreateScoreChangeCommentRequest {
        if (mediaUploadIds != null) {
            mediaUploadIds = Collections.unmodifiableList(new ArrayList<>(mediaUploadIds));
        }
    }

    CreateScoreCommentCommand toCommand() {
        return CreateScoreCommentCommand.from(content, mediaUploadIds);
    }
}

record ParticipantView(int slot, String displayName, boolean mine) {

    ParticipantView {
        if ((slot != 1 && slot != 2) || displayName == null || displayName.isBlank()) {
            throw new IllegalArgumentException("Participant response is invalid");
        }
    }

    static ParticipantView from(ParticipantReference participant, boolean mine) {
        return new ParticipantView(participant.slot(), participant.displayName(), mine);
    }
}

record MediaView(
        UUID id,
        String kind,
        String fileName,
        String contentType,
        long byteSize) {

    MediaView {
        Objects.requireNonNull(id);
        Objects.requireNonNull(kind);
        Objects.requireNonNull(fileName);
        Objects.requireNonNull(contentType);
        if (byteSize <= 0) {
            throw new IllegalArgumentException("Media response size must be positive");
        }
    }

    static MediaView from(AttachedMedia media) {
        return new MediaView(
                media.id(),
                media.kind().name(),
                media.fileName(),
                media.contentType(),
                media.byteSize());
    }
}

record RelationshipScoreView(
        ParticipantView sourceParticipant,
        ParticipantView targetParticipant,
        int currentScore,
        Instant updatedAt) {

    RelationshipScoreView {
        Objects.requireNonNull(sourceParticipant);
        Objects.requireNonNull(targetParticipant);
        Objects.requireNonNull(updatedAt);
        if (currentScore < 0 || currentScore > 100) {
            throw new IllegalArgumentException("Relationship score response is invalid");
        }
    }
}

record ScoreChangeView(
        long id,
        ParticipantView sourceParticipant,
        ParticipantView targetParticipant,
        ParticipantView changedBy,
        int delta,
        int resultingScore,
        String reason,
        Instant createdAt,
        long commentCount,
        List<MediaView> attachments) {

    ScoreChangeView {
        Objects.requireNonNull(sourceParticipant);
        Objects.requireNonNull(targetParticipant);
        Objects.requireNonNull(changedBy);
        Objects.requireNonNull(createdAt);
        attachments = List.copyOf(attachments);
        if (id <= 0
                || delta == 0
                || delta < -100
                || delta > 100
                || resultingScore < 0
                || resultingScore > 100
                || commentCount < 0) {
            throw new IllegalArgumentException("Score change response is invalid");
        }
    }
}

record ScoreChangeCommentView(
        long id,
        ParticipantView author,
        String content,
        Instant createdAt,
        List<MediaView> attachments) {

    ScoreChangeCommentView {
        Objects.requireNonNull(author);
        Objects.requireNonNull(createdAt);
        attachments = List.copyOf(attachments);
        if (id <= 0 || (content == null && attachments.isEmpty())) {
            throw new IllegalArgumentException("Score comment response is invalid");
        }
    }
}

record RelationshipScoresResponse(
        ParticipantView self,
        ParticipantView partner,
        RelationshipScoreView outgoing,
        RelationshipScoreView incoming) {}

record ScoreChangeCreatedResponse(
        ScoreChangeView change,
        RelationshipScoreView outgoing) {}

record ScoreChangeCommentCreatedResponse(ScoreChangeCommentView comment) {}

record ScoreChangeHistoryResponse(List<ScoreChangeView> results, Paging paging) {

    ScoreChangeHistoryResponse {
        results = List.copyOf(results);
    }

    record Paging(int pageNumber, int pageSize, boolean hasNext, long totalCount) {}
}

record ScoreChangeThreadResponse(
        ScoreChangeView change,
        List<ScoreChangeCommentView> comments) {

    ScoreChangeThreadResponse {
        comments = List.copyOf(comments);
    }
}
