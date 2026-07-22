package com.woorisai.notification.internal;

import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(path = "/api/v2/notification-fids")
@RequiredArgsConstructor
class NotificationFidController {

    private final NotificationFidService notificationFids;

    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<Void> register(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long participantId,
            @RequestBody NotificationFidRequest request) {
        notificationFids.register(
                requireParticipant(participantId), requireRequest(request).installationId());
        return noContent();
    }

    @DeleteMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<Void> unregister(
            @AuthenticationPrincipal(errorOnInvalidType = true) Long participantId,
            @RequestBody NotificationFidRequest request) {
        notificationFids.unregister(
                requireParticipant(participantId), requireRequest(request).installationId());
        return noContent();
    }

    private static long requireParticipant(Long participantId) {
        if (participantId == null || participantId <= 0) {
            throw new IllegalArgumentException("Authenticated participant is required");
        }
        return participantId;
    }

    private static NotificationFidRequest requireRequest(NotificationFidRequest request) {
        if (request == null) {
            throw new InvalidNotificationFidException();
        }
        return request;
    }

    private static ResponseEntity<Void> noContent() {
        return ResponseEntity.noContent()
                .cacheControl(CacheControl.noStore())
                .build();
    }
}

record NotificationFidRequest(String fid) {

    FirebaseInstallationId installationId() {
        return FirebaseInstallationId.parse(fid);
    }
}
