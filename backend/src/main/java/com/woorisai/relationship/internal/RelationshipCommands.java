package com.woorisai.relationship.internal;

import java.util.HashSet;
import java.util.List;
import java.util.UUID;

record ChangeScoreCommand(
        ScoreChangeIntent intent,
        String reason,
        List<UUID> mediaUploadIds) {

    static ChangeScoreCommand from(
            Integer delta,
            Integer targetScore,
            String reason,
            List<UUID> mediaUploadIds) {
        try {
            return new ChangeScoreCommand(
                    ScoreChangeIntent.from(delta, targetScore),
                    reason,
                    mediaUploadIds);
        } catch (InvalidScoreChangeIntentException exception) {
            throw new InvalidRelationshipRequestException();
        }
    }

    ChangeScoreCommand {
        if (intent == null) {
            throw new InvalidRelationshipRequestException();
        }
        reason = RelationshipText.optional(reason, 200);
        mediaUploadIds = RelationshipMediaIds.upTo(mediaUploadIds, 1);
    }
}

record CreateScoreCommentCommand(
        String content,
        List<UUID> mediaUploadIds) {

    static CreateScoreCommentCommand from(
            String content,
            List<UUID> mediaUploadIds) {
        return new CreateScoreCommentCommand(content, mediaUploadIds);
    }

    CreateScoreCommentCommand {
        content = RelationshipText.optional(content, 500);
        mediaUploadIds = RelationshipMediaIds.upTo(mediaUploadIds, 4);
        if (content == null && mediaUploadIds.isEmpty()) {
            throw new InvalidRelationshipRequestException();
        }
    }
}

final class RelationshipMediaIds {

    private RelationshipMediaIds() {}

    static List<UUID> upTo(List<UUID> requested, int maximum) {
        if (requested == null) {
            return List.of();
        }
        if (requested.size() > maximum
                || requested.stream().anyMatch(id -> id == null)
                || new HashSet<>(requested).size() != requested.size()) {
            throw new InvalidRelationshipRequestException();
        }
        return List.copyOf(requested);
    }
}
