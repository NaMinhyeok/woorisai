package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import java.time.Clock;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

class MediaConfigurationTest {

    private final ApplicationContextRunner context = new ApplicationContextRunner()
            .withUserConfiguration(MediaConfiguration.class)
            .withBean(Clock.class, Clock::systemUTC)
            .withBean(MediaAttachmentRepository.class, () -> mock(MediaAttachmentRepository.class));

    @Test
    void leavesTheR2RuntimeAbsentByDefault() {
        context.run(result -> {
            assertThat(result).hasNotFailed();
            assertThat(result).doesNotHaveBean(MediaService.class);
            assertThat(result).doesNotHaveBean(R2MediaObjectStorage.class);
            assertThat(result).doesNotHaveBean(S3Client.class);
        });
    }

    @Test
    void wiresOneThinMediaServiceAndTheR2AdapterWhenExplicitlyEnabled() {
        validEnabledContext().run(result -> {
            assertThat(result).hasNotFailed();
            assertThat(result).hasSingleBean(MediaService.class);
            assertThat(result).hasSingleBean(R2MediaObjectStorage.class);
            assertThat(result).hasSingleBean(S3Client.class);
            assertThat(result).hasSingleBean(S3Presigner.class);
        });
    }

    @Test
    void failsClosedWithoutLeakingInvalidCredentialConfiguration() {
        context.withPropertyValues(
                        "woorisai.media.enabled=true",
                        "woorisai.media.endpoint=http://not-private.invalid",
                        "woorisai.media.region=auto",
                        "woorisai.media.bucket=fixture-bucket",
                        "woorisai.media.access-key-id=fixture-access",
                        "woorisai.media.secret-access-key=private-fixture-secret")
                .run(result -> {
                    assertThat(result).hasFailed();
                    assertThat(result.getStartupFailure())
                            .hasMessageNotContaining("private-fixture-secret");
                });
    }

    @Test
    void failsClosedWhenMediaUrlTtlsAreOutsideTheSharedRange() {
        validEnabledContext()
                .withPropertyValues("woorisai.media.upload-url-ttl-seconds=59")
                .run(result -> assertThat(result).hasFailed());

        validEnabledContext()
                .withPropertyValues("woorisai.media.download-url-ttl-seconds=3601")
                .run(result -> assertThat(result).hasFailed());
    }

    private ApplicationContextRunner validEnabledContext() {
        return context.withPropertyValues(
                "woorisai.media.enabled=true",
                "woorisai.media.endpoint=https://synthetic-account.r2.invalid",
                "woorisai.media.region=auto",
                "woorisai.media.bucket=fixture-bucket",
                "woorisai.media.access-key-id=fixture-access",
                "woorisai.media.secret-access-key=fixture-secret",
                "woorisai.media.upload-url-ttl-seconds=900",
                "woorisai.media.download-url-ttl-seconds=300");
    }
}
