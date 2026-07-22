package com.woorisai.identity.internal;

import java.util.List;

record LoginOptionsResponse(List<LoginParticipantOption> participants) {

    LoginOptionsResponse {
        participants = List.copyOf(participants);
    }
}
