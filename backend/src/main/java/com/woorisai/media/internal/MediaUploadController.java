package com.woorisai.media.internal;

import jakarta.validation.Valid;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
class MediaUploadController {

    private final Optional<MediaService> media;

    @PostMapping(
            path = "/api/v2/media-uploads",
            consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<InitiatedMediaUploadResponse> initiate(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @Valid @RequestBody InitiateMediaUploadRequest request) {
        MediaService operation = media
                .orElseThrow(MediaUploadsUnavailableHttpException::new);

        InitiatedMediaUpload upload = operation.initiate(
                MediaHttpActors.require(actorId),
                request.mediaPurpose(),
                request.mediaKind(),
                request.fileName(),
                request.contentType(),
                request.byteSize());
        return ResponseEntity.status(201)
                .cacheControl(CacheControl.noStore())
                .body(InitiatedMediaUploadResponse.from(upload));
    }

    @PostMapping(
            path = "/api/v2/media-uploads/{uploadId}/complete",
            produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<CompletedMediaUploadResponse> complete(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable String uploadId,
            @RequestBody(required = false) byte[] requestBody) {
        MediaUploadHttpBodies.requireEmpty(requestBody);
        MediaService operation = media
                .orElseThrow(MediaUploadsUnavailableHttpException::new);
        CompletedMediaUpload upload = operation.complete(
                MediaHttpActors.require(actorId), MediaUploadHttpIds.parse(uploadId));
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(CompletedMediaUploadResponse.from(upload));
    }

    @DeleteMapping("/api/v2/media-uploads/{uploadId}")
    ResponseEntity<Void> discard(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable String uploadId,
            @RequestBody(required = false) byte[] requestBody) {
        MediaUploadHttpBodies.requireEmpty(requestBody);
        MediaService operation = media
                .orElseThrow(MediaUploadsUnavailableHttpException::new);
        operation.discard(
                MediaHttpActors.require(actorId), MediaUploadHttpIds.parse(uploadId));
        return ResponseEntity.noContent()
                .cacheControl(CacheControl.noStore())
                .build();
    }
}
