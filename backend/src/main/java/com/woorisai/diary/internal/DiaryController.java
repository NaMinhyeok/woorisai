package com.woorisai.diary.internal;

import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
class DiaryController {

    private final DiaryService diary;

    @GetMapping(
            path = "/api/v2/diary-entries",
            produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<DiaryEntryListResponse> listEntries(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @RequestParam(name = "pageNumber", defaultValue = "1") int pageNumber) {
        requirePositive(pageNumber);
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(diary.listEntries(requireActor(actorId), pageNumber));
    }

    @PostMapping(
            path = "/api/v2/diary-entries",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<DiaryEntryCreatedResponse> createEntry(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @RequestBody CreateDiaryEntryRequest request) {
        CreateDiaryEntryCommand command = requireRequest(request).toCommand();
        return ResponseEntity.status(201)
                .cacheControl(CacheControl.noStore())
                .body(diary.createEntry(requireActor(actorId), command));
    }

    @GetMapping(
            path = "/api/v2/diary-entries/{entryId}",
            produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<DiaryEntryDetailResponse> getEntry(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable("entryId") long entryId) {
        requirePositive(entryId);
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(diary.getEntry(requireActor(actorId), entryId));
    }

    @PatchMapping(
            path = "/api/v2/diary-entries/{entryId}",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<DiaryEntryUpdatedResponse> updateEntry(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable("entryId") long entryId,
            @RequestBody UpdateDiaryEntryRequest request) {
        requirePositive(entryId);
        UpdateDiaryEntryCommand command = requireRequest(request).toCommand();
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(diary.updateEntry(requireActor(actorId), entryId, command));
    }

    @DeleteMapping("/api/v2/diary-entries/{entryId}")
    ResponseEntity<Void> deleteEntry(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable("entryId") long entryId) {
        requirePositive(entryId);
        diary.deleteEntry(requireActor(actorId), entryId);
        return ResponseEntity.noContent()
                .cacheControl(CacheControl.noStore())
                .build();
    }

    @PostMapping(
            path = "/api/v2/diary-entries/{entryId}/comments",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<DiaryEntryCommentCreatedResponse> createComment(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable("entryId") long entryId,
            @RequestBody CreateDiaryCommentRequest request) {
        requirePositive(entryId);
        CreateDiaryCommentCommand command = requireRequest(request).toCommand();
        return ResponseEntity.status(201)
                .cacheControl(CacheControl.noStore())
                .body(diary.createComment(requireActor(actorId), entryId, command));
    }

    @PatchMapping(
            path = "/api/v2/diary-entry-comments/{commentId}",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<DiaryEntryCommentUpdatedResponse> updateComment(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable("commentId") long commentId,
            @RequestBody UpdateDiaryCommentRequest request) {
        requirePositive(commentId);
        UpdateDiaryCommentCommand command = requireRequest(request).toCommand();
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(diary.updateComment(requireActor(actorId), commentId, command));
    }

    @DeleteMapping("/api/v2/diary-entry-comments/{commentId}")
    ResponseEntity<Void> deleteComment(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable("commentId") long commentId) {
        requirePositive(commentId);
        diary.deleteComment(requireActor(actorId), commentId);
        return ResponseEntity.noContent()
                .cacheControl(CacheControl.noStore())
                .build();
    }

    private static long requireActor(Long actorId) {
        if (actorId == null || actorId <= 0) {
            throw new InvalidDiaryRequestException();
        }
        return actorId;
    }

    private static <T> T requireRequest(T request) {
        if (request == null) {
            throw new InvalidDiaryRequestException();
        }
        return request;
    }

    private static void requirePositive(long value) {
        if (value <= 0) {
            throw new InvalidDiaryRequestException();
        }
    }
}
