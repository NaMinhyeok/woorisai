package com.woorisai.notification.internal;

import com.google.auth.oauth2.ServiceAccountCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import com.woorisai.notification.internal.NotificationSender.NotificationDeliveryUnavailableException;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Arrays;
import java.util.Base64;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(FirebaseNotificationProperties.class)
class NotificationConfiguration {

    @Configuration(proxyBeanMethods = false)
    @ConditionalOnProperty(
            prefix = "woorisai.notification.firebase",
            name = "enabled",
            havingValue = "true")
    static class EnabledFirebaseConfiguration {

        private static final String FIREBASE_APP_NAME = "woorisai-notification";

        @Bean(name = "notificationFirebaseApp", destroyMethod = "delete")
        FirebaseApp notificationFirebaseApp(FirebaseNotificationProperties properties) {
            String projectId = requireProjectId(properties.projectId());
            FirebaseOptions options = FirebaseOptions.builder()
                    .setProjectId(projectId)
                    .setCredentials(serviceAccount(properties.serviceAccountJsonBase64()))
                    .build();
            return FirebaseApp.initializeApp(options, FIREBASE_APP_NAME);
        }

        @Bean
        NotificationSender firebaseNotificationSender(
                @Qualifier("notificationFirebaseApp") FirebaseApp firebaseApp) {
            return new FirebaseNotificationSender(FirebaseMessaging.getInstance(firebaseApp));
        }

        private static String requireProjectId(String projectId) {
            if (projectId == null || projectId.isBlank()) {
                throw new IllegalStateException("Firebase project ID is required");
            }
            return projectId;
        }

        private static ServiceAccountCredentials serviceAccount(String encodedJson) {
            if (encodedJson == null || encodedJson.isBlank()) {
                throw new IllegalStateException("Firebase service account JSON is required");
            }

            byte[] json;
            try {
                json = Base64.getDecoder().decode(encodedJson);
            } catch (IllegalArgumentException exception) {
                throw new IllegalStateException("Firebase service account JSON is invalid");
            }

            try (ByteArrayInputStream input = new ByteArrayInputStream(json)) {
                return ServiceAccountCredentials.fromStream(input);
            } catch (IOException | RuntimeException exception) {
                throw new IllegalStateException("Firebase service account JSON is invalid");
            } finally {
                Arrays.fill(json, (byte) 0);
            }
        }
    }

    @Configuration(proxyBeanMethods = false)
    @ConditionalOnProperty(
            prefix = "woorisai.notification.firebase",
            name = "enabled",
            havingValue = "false",
            matchIfMissing = true)
    static class DisabledFirebaseConfiguration {

        @Bean
        NotificationSender disabledNotificationSender() {
            return message -> {
                throw new NotificationDeliveryUnavailableException();
            };
        }
    }
}
