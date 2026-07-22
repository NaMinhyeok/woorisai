package com.woorisai.notification.internal;

import com.woorisai.diary.DiaryEntryCommentCreated;
import com.woorisai.notification.internal.NotificationSender.InvalidNotificationTargetException;
import com.woorisai.notification.internal.NotificationSender.NotificationEventType;
import com.woorisai.notification.internal.NotificationSender.NotificationMessage;
import com.woorisai.relationship.RelationshipScoreChanged;
import com.woorisai.relationship.ScoreChangeCommentCreated;
import lombok.RequiredArgsConstructor;
import org.springframework.modulith.events.ApplicationModuleListener;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
class NotificationEventListener {

    static final String RELATIONSHIP_SCORE_CHANGED_LISTENER =
            "notification.relationship-score-changed";
    static final String SCORE_CHANGE_COMMENT_CREATED_LISTENER =
            "notification.score-change-comment-created";
    static final String DIARY_ENTRY_COMMENT_CREATED_LISTENER =
            "notification.diary-entry-comment-created";

    private final NotificationFidRepository fids;
    private final NotificationSender sender;

    @ApplicationModuleListener(id = RELATIONSHIP_SCORE_CHANGED_LISTENER)
    void relationshipScoreChanged(RelationshipScoreChanged event) {
        deliver(
                event.recipientParticipantId(),
                NotificationEventType.RELATIONSHIP_SCORE_CHANGED,
                event.scoreChangeId());
    }

    @ApplicationModuleListener(id = SCORE_CHANGE_COMMENT_CREATED_LISTENER)
    void scoreChangeCommentCreated(ScoreChangeCommentCreated event) {
        deliver(
                event.recipientParticipantId(),
                NotificationEventType.SCORE_CHANGE_COMMENT_CREATED,
                event.scoreChangeId());
    }

    @ApplicationModuleListener(id = DIARY_ENTRY_COMMENT_CREATED_LISTENER)
    void diaryEntryCommentCreated(DiaryEntryCommentCreated event) {
        deliver(
                event.recipientParticipantId(),
                NotificationEventType.DIARY_ENTRY_COMMENT_CREATED,
                event.diaryEntryId());
    }

    private void deliver(
            long recipientParticipantId,
            NotificationEventType eventType,
            long resourceId) {
        for (NotificationFid target
                : fids.findAllByParticipantIdOrderByIdAsc(recipientParticipantId)) {
            try {
                sender.send(new NotificationMessage(target.installationId(), eventType, resourceId));
            } catch (InvalidNotificationFidException | InvalidNotificationTargetException exception) {
                fids.deleteByFid(target.getFid());
            }
        }
    }
}
