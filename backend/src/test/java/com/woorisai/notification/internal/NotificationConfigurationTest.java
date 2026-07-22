package com.woorisai.notification.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.notification.internal.NotificationSender.NotificationDeliveryUnavailableException;
import com.woorisai.notification.internal.NotificationSender.NotificationDeliveryFailureCategory;
import com.woorisai.notification.internal.NotificationSender.NotificationEventType;
import com.woorisai.notification.internal.NotificationSender.NotificationMessage;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

class NotificationConfigurationTest {

    private static final String FID = "c123456789012345678901";
    private static final FirebaseInstallationId INSTALLATION_ID =
            FirebaseInstallationId.parse(FID);

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withUserConfiguration(NotificationConfiguration.class);

    @Test
    void keepsTheListenerFacingSenderBeanWhenFirebaseIsDisabled() {
        contextRunner.run(context -> {
            NotificationSender sender = context.getBean(NotificationSender.class);

            assertThatThrownBy(() -> sender.send(new NotificationMessage(
                            INSTALLATION_ID,
                            NotificationEventType.SCORE_CHANGE_COMMENT_CREATED,
                            41)))
                    .isInstanceOf(NotificationDeliveryUnavailableException.class)
                    .hasMessage("Notification delivery failed [category=CONFIGURATION]")
                    .hasNoCause()
                    .satisfies(exception -> assertThat(
                            ((NotificationDeliveryUnavailableException) exception)
                                    .failureCategory())
                            .isEqualTo(NotificationDeliveryFailureCategory.CONFIGURATION));
        });
    }

    @Test
    void failsFastWithoutFallingBackToAmbientCredentialsWhenEnabled() {
        contextRunner
                .withPropertyValues("woorisai.notification.firebase.enabled=true")
                .run(context -> assertThatThrownBy(() -> context.getBean(NotificationSender.class))
                        .isInstanceOf(RuntimeException.class));
    }

}
