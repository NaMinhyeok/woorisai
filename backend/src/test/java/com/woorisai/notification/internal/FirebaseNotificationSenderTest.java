package com.woorisai.notification.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.google.firebase.ErrorCode;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;
import com.google.firebase.messaging.Notification;
import com.woorisai.notification.internal.NotificationSender.InvalidNotificationTargetException;
import com.woorisai.notification.internal.NotificationSender.NotificationDeliveryException;
import com.woorisai.notification.internal.NotificationSender.NotificationDeliveryFailureCategory;
import com.woorisai.notification.internal.NotificationSender.NotificationEventType;
import com.woorisai.notification.internal.NotificationSender.NotificationMessage;
import java.lang.reflect.Field;
import java.util.Map;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

class FirebaseNotificationSenderTest {

    private static final String FID = "c123456789012345678901";
    private static final FirebaseInstallationId INSTALLATION_ID =
            FirebaseInstallationId.parse(FID);

    @Test
    void buildsAPrivacySafeFidMessageWithoutUsingTheDeprecatedTokenField() {
        FirebaseNotificationSender sender = new FirebaseNotificationSender(
                mock(FirebaseMessaging.class));

        Message message = sender.message(new NotificationMessage(
                INSTALLATION_ID,
                NotificationEventType.RELATIONSHIP_SCORE_CHANGED,
                41));

        assertThat(field(message, "fid")).isEqualTo(FID);
        assertThat(field(message, "token")).isNull();
        assertThat(field(message, "data")).isEqualTo(Map.of(
                "eventType", "relationshipScoreChanged",
                "resourceId", "41"));

        Notification notification = (Notification) field(message, "notification");
        assertThat(field(notification, "title")).isEqualTo("우리 사이");
        assertThat(field(notification, "body")).isEqualTo("새로운 마음 기록이 도착했어요");
        assertThat(field(notification, "image")).isNull();
    }

    @Test
    void treatsOnlyUnregisteredAsAPermanentlyInvalidTarget()
            throws Exception {
        FirebaseMessaging messaging = mock(FirebaseMessaging.class);
        FirebaseMessagingException unregistered = mock(FirebaseMessagingException.class);
        when(unregistered.getMessagingErrorCode()).thenReturn(MessagingErrorCode.UNREGISTERED);
        when(messaging.send(any(Message.class))).thenThrow(unregistered);
        FirebaseNotificationSender sender = new FirebaseNotificationSender(messaging);

        assertThatThrownBy(() -> sender.send(message()))
                .isInstanceOf(InvalidNotificationTargetException.class);
    }

    @ParameterizedTest
    @MethodSource("providerFailureCategories")
    void preservesOnlyAPrivacySafeProviderFailureCategory(
            MessagingErrorCode messagingErrorCode,
            ErrorCode errorCode,
            NotificationDeliveryFailureCategory expectedCategory) throws Exception {
        FirebaseMessaging messaging = mock(FirebaseMessaging.class);
        FirebaseMessagingException providerFailure = mock(FirebaseMessagingException.class);
        when(providerFailure.getMessagingErrorCode()).thenReturn(messagingErrorCode);
        when(providerFailure.getErrorCode()).thenReturn(errorCode);
        when(providerFailure.getMessage()).thenReturn("sensitive provider response");
        when(messaging.send(any(Message.class))).thenThrow(providerFailure);
        FirebaseNotificationSender sender = new FirebaseNotificationSender(messaging);

        assertThatThrownBy(() -> sender.send(message()))
                .isExactlyInstanceOf(NotificationDeliveryException.class)
                .hasMessage("Notification delivery failed [category=" + expectedCategory + "]")
                .hasNoCause()
                .satisfies(exception -> assertThat(
                                ((NotificationDeliveryException) exception).failureCategory())
                        .isEqualTo(expectedCategory));
    }

    @Test
    void sanitizesUnexpectedRuntimeFailureAsUnknown() throws Exception {
        FirebaseMessaging messaging = mock(FirebaseMessaging.class);
        when(messaging.send(any(Message.class)))
                .thenThrow(new IllegalStateException("sensitive provider response"));
        FirebaseNotificationSender sender = new FirebaseNotificationSender(messaging);

        assertThatThrownBy(() -> sender.send(message()))
                .isExactlyInstanceOf(NotificationDeliveryException.class)
                .hasMessage("Notification delivery failed [category=UNKNOWN]")
                .hasNoCause()
                .satisfies(exception -> assertThat(
                                ((NotificationDeliveryException) exception).failureCategory())
                        .isEqualTo(NotificationDeliveryFailureCategory.UNKNOWN));
    }

    private static Stream<Arguments> providerFailureCategories() {
        return Stream.of(
                Arguments.of(
                        MessagingErrorCode.THIRD_PARTY_AUTH_ERROR,
                        null,
                        NotificationDeliveryFailureCategory.APNS_AUTH),
                Arguments.of(
                        MessagingErrorCode.SENDER_ID_MISMATCH,
                        null,
                        NotificationDeliveryFailureCategory.PROJECT),
                Arguments.of(
                        null,
                        ErrorCode.UNAUTHENTICATED,
                        NotificationDeliveryFailureCategory.AUTH),
                Arguments.of(
                        null,
                        ErrorCode.PERMISSION_DENIED,
                        NotificationDeliveryFailureCategory.AUTH),
                Arguments.of(
                        MessagingErrorCode.UNAVAILABLE,
                        null,
                        NotificationDeliveryFailureCategory.TRANSIENT),
                Arguments.of(
                        MessagingErrorCode.INTERNAL,
                        null,
                        NotificationDeliveryFailureCategory.TRANSIENT),
                Arguments.of(
                        null,
                        ErrorCode.DEADLINE_EXCEEDED,
                        NotificationDeliveryFailureCategory.TRANSIENT),
                Arguments.of(
                        MessagingErrorCode.QUOTA_EXCEEDED,
                        null,
                        NotificationDeliveryFailureCategory.QUOTA),
                Arguments.of(
                        null,
                        ErrorCode.RESOURCE_EXHAUSTED,
                        NotificationDeliveryFailureCategory.QUOTA),
                Arguments.of(
                        MessagingErrorCode.INVALID_ARGUMENT,
                        ErrorCode.INVALID_ARGUMENT,
                        NotificationDeliveryFailureCategory.UNKNOWN),
                Arguments.of(
                        null,
                        ErrorCode.UNKNOWN,
                        NotificationDeliveryFailureCategory.UNKNOWN));
    }

    private NotificationMessage message() {
        return new NotificationMessage(
                INSTALLATION_ID,
                NotificationEventType.DIARY_ENTRY_COMMENT_CREATED,
                51);
    }

    private static Object field(Object target, String name) {
        try {
            Field field = target.getClass().getDeclaredField(name);
            field.setAccessible(true);
            return field.get(target);
        } catch (ReflectiveOperationException exception) {
            throw new AssertionError(exception);
        }
    }
}
