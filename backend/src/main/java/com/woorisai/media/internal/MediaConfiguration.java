package com.woorisai.media.internal;

import java.net.URI;
import java.net.URISyntaxException;
import java.time.Clock;
import java.time.Duration;
import java.util.UUID;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.checksums.RequestChecksumCalculation;
import software.amazon.awssdk.core.checksums.ResponseChecksumValidation;
import software.amazon.awssdk.core.client.config.ClientOverrideConfiguration;
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.retries.DefaultRetryStrategy;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(MediaProperties.class)
class MediaConfiguration {

    @Configuration(proxyBeanMethods = false)
    @ConditionalOnProperty(prefix = "woorisai.media", name = "enabled", havingValue = "true")
    static class EnabledMediaConfiguration {

        private static final Duration CONNECT_TIMEOUT = Duration.ofSeconds(2);
        private static final Duration OPERATION_TIMEOUT = Duration.ofSeconds(5);

        private final EnabledMediaProperties properties;

        EnabledMediaConfiguration(MediaProperties properties) {
            this.properties = EnabledMediaProperties.from(properties);
        }

        @Bean(destroyMethod = "close")
        S3Client mediaS3Client() {
            return S3Client.builder()
                    .endpointOverride(properties.endpoint())
                    .region(Region.of(properties.region()))
                    .credentialsProvider(credentials())
                    .serviceConfiguration(s3Configuration())
                    .requestChecksumCalculation(RequestChecksumCalculation.WHEN_REQUIRED)
                    .responseChecksumValidation(ResponseChecksumValidation.WHEN_REQUIRED)
                    .overrideConfiguration(ClientOverrideConfiguration.builder()
                            .retryStrategy(DefaultRetryStrategy.doNotRetry())
                            .apiCallTimeout(OPERATION_TIMEOUT)
                            .apiCallAttemptTimeout(OPERATION_TIMEOUT)
                            .build())
                    .httpClientBuilder(UrlConnectionHttpClient.builder()
                            .connectionTimeout(CONNECT_TIMEOUT)
                            .socketTimeout(OPERATION_TIMEOUT))
                    .build();
        }

        @Bean(destroyMethod = "close")
        S3Presigner mediaS3Presigner() {
            return S3Presigner.builder()
                    .endpointOverride(properties.endpoint())
                    .region(Region.of(properties.region()))
                    .credentialsProvider(credentials())
                    .serviceConfiguration(s3Configuration())
                    .build();
        }

        @Bean
        R2MediaObjectStorage r2MediaObjectStorage(
                S3Client mediaS3Client,
                S3Presigner mediaS3Presigner) {
            return new R2MediaObjectStorage(
                    mediaS3Client,
                    mediaS3Presigner,
                    properties.bucket());
        }

        @Bean
        MediaService mediaService(
                MediaAttachmentRepository attachments,
                R2MediaObjectStorage objects,
                Clock clock) {
            return new MediaService(
                    attachments,
                    objects,
                    new MediaPolicy(properties.uploadUrlTtlSeconds()),
                    properties.downloadUrlTtlSeconds(),
                    clock,
                    UUID::randomUUID);
        }

        private StaticCredentialsProvider credentials() {
            return StaticCredentialsProvider.create(AwsBasicCredentials.create(
                    properties.accessKeyId(), properties.secretAccessKey()));
        }

        private static S3Configuration s3Configuration() {
            return S3Configuration.builder()
                    .pathStyleAccessEnabled(true)
                    .chunkedEncodingEnabled(false)
                    .build();
        }
    }

    private record EnabledMediaProperties(
            URI endpoint,
            String region,
            String bucket,
            String accessKeyId,
            String secretAccessKey,
            int uploadUrlTtlSeconds,
            int downloadUrlTtlSeconds) {

        private static EnabledMediaProperties from(MediaProperties properties) {
            if (properties == null) {
                throw invalidConfiguration();
            }
            URI endpoint = endpoint(properties.endpoint());
            String region = requireText(properties.region());
            String bucket = requireText(properties.bucket());
            String accessKeyId = requireText(properties.accessKeyId());
            String secretAccessKey = requireText(properties.secretAccessKey());
            int uploadTtl = MediaUrlTtl.requireSeconds(
                    properties.uploadUrlTtlSeconds(), EnabledMediaProperties::invalidConfiguration);
            int downloadTtl = MediaUrlTtl.requireSeconds(
                    properties.downloadUrlTtlSeconds(), EnabledMediaProperties::invalidConfiguration);
            return new EnabledMediaProperties(
                    endpoint,
                    region,
                    bucket,
                    accessKeyId,
                    secretAccessKey,
                    uploadTtl,
                    downloadTtl);
        }

        private static URI endpoint(String configuredEndpoint) {
            if (configuredEndpoint == null || configuredEndpoint.isBlank()) {
                throw invalidConfiguration();
            }
            String normalized = configuredEndpoint.trim();
            while (normalized.endsWith("/")) {
                normalized = normalized.substring(0, normalized.length() - 1);
            }
            URI endpoint;
            try {
                endpoint = new URI(normalized);
            } catch (URISyntaxException exception) {
                throw invalidConfiguration();
            }
            if (!"https".equalsIgnoreCase(endpoint.getScheme())
                    || endpoint.getHost() == null
                    || endpoint.getHost().isBlank()
                    || endpoint.getRawQuery() != null
                    || endpoint.getRawFragment() != null
                    || endpoint.getRawUserInfo() != null) {
                throw invalidConfiguration();
            }
            return endpoint;
        }

        private static String requireText(String value) {
            if (value == null || value.isBlank()) {
                throw invalidConfiguration();
            }
            return value.trim();
        }

        private static IllegalStateException invalidConfiguration() {
            return new IllegalStateException("Media runtime configuration is invalid");
        }
    }
}
