package com.woorisai.media.internal;

import java.util.Optional;
import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
class MediaAttachmentDownloadController {

    private final Optional<MediaService> media;

    @GetMapping(
            path = "/api/v2/media-attachments/{attachmentId}/download-url",
            produces = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<MediaDownloadUrlResponse> download(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long actorId,
            @PathVariable String attachmentId) {
        MediaService operation = media.orElseThrow(
                MediaAttachmentDownloadUnavailableException::new);
        MediaDownloadGrant grant = operation.download(
                MediaAttachmentDownloadHttpIds.requireActor(actorId),
                MediaAttachmentDownloadHttpIds.parse(attachmentId));
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(MediaDownloadUrlResponse.from(grant));
    }
}
