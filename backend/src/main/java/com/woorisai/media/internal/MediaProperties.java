package com.woorisai.media.internal;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("woorisai.media")
record MediaProperties(
        boolean enabled,
        String endpoint,
        String region,
        String bucket,
        String accessKeyId,
        String secretAccessKey,
        Integer uploadUrlTtlSeconds,
        Integer downloadUrlTtlSeconds) {

    MediaProperties {
        if (region == null) {
            region = "auto";
        }
        if (uploadUrlTtlSeconds == null) {
            uploadUrlTtlSeconds = 900;
        }
        if (downloadUrlTtlSeconds == null) {
            downloadUrlTtlSeconds = 300;
        }
    }
}
