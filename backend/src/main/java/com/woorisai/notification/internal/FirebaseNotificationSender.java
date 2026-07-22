package com.woorisai.notification.internal;

import com.google.firebase.ErrorCode;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;
import com.google.firebase.messaging.Notification;
import com.woorisai.notification.internal.NotificationSender.InvalidNotificationTargetException;
import com.woorisai.notification.internal.NotificationSender.NotificationDeliveryException;
import com.woorisai.notification.internal.NotificationSender.NotificationDeliveryFailureCategory;
import com.woorisai.notification.internal.NotificationSender.NotificationMessage;
import lombok.RequiredArgsConstructor;

@RequiredArgsConstructor
final class FirebaseNotificationSender implements NotificationSender {

    private static final String TITLE = "우리 사이";

    private final FirebaseMessaging messaging;

    @Override
    public void send(NotificationMessage notification) {
        try {
            messaging.send(message(notification));
        } catch (FirebaseMessagingException exception) {
            if (exception.getMessagingErrorCode() == MessagingErrorCode.UNREGISTERED) {
                throw new InvalidNotificationTargetException();
            }
            throw new NotificationDeliveryException(failureCategory(exception));
        } catch (RuntimeException exception) {
            throw new NotificationDeliveryException(
                    NotificationDeliveryFailureCategory.UNKNOWN);
        }
    }

    Message message(NotificationMessage notification) {
        return Message.builder()
                .setFid(notification.targetFid().value())
                .setNotification(Notification.builder()
                        .setTitle(TITLE)
                        .setBody(notification.eventType().body())
                        .build())
                .putData("eventType", notification.eventType().wireName())
                .putData("resourceId", Long.toString(notification.resourceId()))
                .build();
    }

    private static NotificationDeliveryFailureCategory failureCategory(
            FirebaseMessagingException exception) {
        MessagingErrorCode messagingErrorCode = exception.getMessagingErrorCode();
        if (messagingErrorCode != null) {
            return switch (messagingErrorCode) {
                case THIRD_PARTY_AUTH_ERROR -> NotificationDeliveryFailureCategory.APNS_AUTH;
                case SENDER_ID_MISMATCH -> NotificationDeliveryFailureCategory.PROJECT;
                case QUOTA_EXCEEDED -> NotificationDeliveryFailureCategory.QUOTA;
                case INTERNAL, UNAVAILABLE -> NotificationDeliveryFailureCategory.TRANSIENT;
                case INVALID_ARGUMENT, UNREGISTERED ->
                    fallbackFailureCategory(exception.getErrorCode());
            };
        }
        return fallbackFailureCategory(exception.getErrorCode());
    }

    private static NotificationDeliveryFailureCategory fallbackFailureCategory(
            ErrorCode errorCode) {
        if (errorCode == null) {
            return NotificationDeliveryFailureCategory.UNKNOWN;
        }
        return switch (errorCode) {
            case UNAUTHENTICATED, PERMISSION_DENIED ->
                NotificationDeliveryFailureCategory.AUTH;
            case RESOURCE_EXHAUSTED -> NotificationDeliveryFailureCategory.QUOTA;
            case ABORTED, CANCELLED, DEADLINE_EXCEEDED, INTERNAL, UNAVAILABLE ->
                NotificationDeliveryFailureCategory.TRANSIENT;
            default -> NotificationDeliveryFailureCategory.UNKNOWN;
        };
    }
}
