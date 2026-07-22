package com.woorisai.identity.internal;

import com.woorisai.participant.ParticipantDirectory;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
class LoginOptionsController {

    private final ParticipantDirectory participants;

    @GetMapping("/api/v2/auth/login-options")
    ResponseEntity<LoginOptionsResponse> listLoginOptions() {
        List<LoginParticipantOption> options = participants.canonicalPair()
                .inSlotOrder()
                .stream()
                .map(LoginParticipantOption::from)
                .toList();

        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(new LoginOptionsResponse(options));
    }
}
