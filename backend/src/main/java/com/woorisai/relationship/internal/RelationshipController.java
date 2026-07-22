package com.woorisai.relationship.internal;

import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(path = "/api/v2", produces = MediaType.APPLICATION_JSON_VALUE)
@RequiredArgsConstructor
class RelationshipController {

    private final RelationshipService relationships;

    @GetMapping("/relationship-scores")
    ResponseEntity<RelationshipScoresResponse> relationshipScores(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId) {
        return ok(relationships.relationshipScores(requireActor(actorId)));
    }

    @GetMapping("/score-changes")
    ResponseEntity<ScoreChangeHistoryResponse> scoreChanges(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @RequestParam(defaultValue = "1") int pageNumber) {
        requirePositive(pageNumber);
        return ok(relationships.scoreChanges(requireActor(actorId), pageNumber));
    }

    @PostMapping(path = "/score-changes", consumes = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<ScoreChangeCreatedResponse> changeScore(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @RequestBody ChangeScoreRequest request) {
        if (request == null) {
            throw new InvalidRelationshipRequestException();
        }
        return created(relationships.changeScore(requireActor(actorId), request.toCommand()));
    }

    @GetMapping("/score-changes/{scoreChangeId}")
    ResponseEntity<ScoreChangeThreadResponse> scoreChange(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable long scoreChangeId) {
        requirePositive(scoreChangeId);
        return ok(relationships.scoreChange(requireActor(actorId), scoreChangeId));
    }

    @PostMapping(
            path = "/score-changes/{scoreChangeId}/comments",
            consumes = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<ScoreChangeCommentCreatedResponse> createComment(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable long scoreChangeId,
            @RequestBody CreateScoreChangeCommentRequest request) {
        requirePositive(scoreChangeId);
        if (request == null) {
            throw new InvalidRelationshipRequestException();
        }
        return created(relationships.createComment(
                requireActor(actorId), scoreChangeId, request.toCommand()));
    }

    private long requireActor(Long actorId) {
        if (actorId == null || actorId <= 0) {
            throw new InvalidRelationshipRequestException();
        }
        return actorId;
    }

    private void requirePositive(long value) {
        if (value <= 0) {
            throw new InvalidRelationshipRequestException();
        }
    }

    private <T> ResponseEntity<T> ok(T body) {
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(body);
    }

    private <T> ResponseEntity<T> created(T body) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .cacheControl(CacheControl.noStore())
                .body(body);
    }
}
