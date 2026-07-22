package com.woorisai.notification.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("woorisai.notification.firebase")
record FirebaseNotificationProperties(
        boolean enabled,
        String projectId,
        String serviceAccountJsonBase64) {}
