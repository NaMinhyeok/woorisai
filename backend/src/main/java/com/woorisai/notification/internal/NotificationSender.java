package com.woorisai.notification.internal;

import java.util.Objects;

interface NotificationSender {

    void send(NotificationMessage message);

    enum NotificationEventType {
        RELATIONSHIP_SCORE_CHANGED("relationshipScoreChanged", "새로운 마음 기록이 도착했어요"),
        SCORE_CHANGE_COMMENT_CREATED("scoreChangeCommentCreated", "새로운 댓글이 도착했어요"),
        DIARY_ENTRY_COMMENT_CREATED("diaryEntryCommentCreated", "새로운 댓글이 도착했어요");

        private final String wireName;
        private final String body;

        NotificationEventType(String wireName, String body) {
            this.wireName = wireName;
            this.body = body;
        }

        String wireName() {
            return wireName;
        }

        String body() {
            return body;
        }
    }

    record NotificationMessage(
            FirebaseInstallationId targetFid,
            NotificationEventType eventType,
            long resourceId) {

        public NotificationMessage {
            Objects.requireNonNull(targetFid);
            if (eventType == null || resourceId <= 0) {
                throw new IllegalArgumentException("Notification payload is invalid");
            }
        }
    }

    final class InvalidNotificationTargetException extends RuntimeException {

        InvalidNotificationTargetException() {
            super("Notification target is invalid");
        }
    }

    enum NotificationDeliveryFailureCategory {
        APNS_AUTH,
        PROJECT,
        AUTH,
        TRANSIENT,
        QUOTA,
        CONFIGURATION,
        UNKNOWN
    }

    class NotificationDeliveryException extends RuntimeException {

        private final NotificationDeliveryFailureCategory failureCategory;

        NotificationDeliveryException() {
            this(NotificationDeliveryFailureCategory.UNKNOWN);
        }

        NotificationDeliveryException(NotificationDeliveryFailureCategory failureCategory) {
            super("Notification delivery failed [category="
                    + Objects.requireNonNull(failureCategory)
                    + "]");
            this.failureCategory = failureCategory;
        }

        NotificationDeliveryFailureCategory failureCategory() {
            return failureCategory;
        }
    }

    final class NotificationDeliveryUnavailableException extends NotificationDeliveryException {

        NotificationDeliveryUnavailableException() {
            super(NotificationDeliveryFailureCategory.CONFIGURATION);
        }
    }
}
