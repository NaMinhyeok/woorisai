package com.woorisai.notification.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.woorisai.diary.DiaryEntryCommentCreated;
import com.woorisai.notification.internal.NotificationSender.InvalidNotificationTargetException;
import com.woorisai.notification.internal.NotificationSender.NotificationDeliveryException;
import com.woorisai.notification.internal.NotificationSender.NotificationEventType;
import com.woorisai.notification.internal.NotificationSender.NotificationMessage;
import com.woorisai.relationship.RelationshipScoreChanged;
import com.woorisai.relationship.ScoreChangeCommentCreated;
import java.lang.reflect.Method;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.modulith.events.ApplicationModuleListener;

class NotificationEventListenerTest {

    private static final String FIRST_FID = "c123456789012345678901";
    private static final String SECOND_FID = "d123456789012345678901";
    private static final FirebaseInstallationId FIRST_INSTALLATION_ID =
            FirebaseInstallationId.parse(FIRST_FID);
    private static final FirebaseInstallationId SECOND_INSTALLATION_ID =
            FirebaseInstallationId.parse(SECOND_FID);

    private NotificationFidRepository fids;
    private RecordingSender sender;
    private NotificationEventListener listener;

    @BeforeEach
    void setUp() {
        fids = mock(NotificationFidRepository.class);
        sender = new RecordingSender();
        listener = new NotificationEventListener(fids, sender);
    }

    @Test
    void sendsOnlyGenericNavigationDataInStableRepositoryOrder() {
        when(fids.findAllByParticipantIdOrderByIdAsc(2L)).thenReturn(List.of(
                target(FIRST_FID),
                target(SECOND_FID)));

        listener.relationshipScoreChanged(new RelationshipScoreChanged(2, 41));
        listener.scoreChangeCommentCreated(new ScoreChangeCommentCreated(2, 42));
        listener.diaryEntryCommentCreated(new DiaryEntryCommentCreated(2, 51));

        assertThat(sender.messages).containsExactly(
                new NotificationMessage(
                        FIRST_INSTALLATION_ID,
                        NotificationEventType.RELATIONSHIP_SCORE_CHANGED,
                        41),
                new NotificationMessage(
                        SECOND_INSTALLATION_ID,
                        NotificationEventType.RELATIONSHIP_SCORE_CHANGED,
                        41),
                new NotificationMessage(
                        FIRST_INSTALLATION_ID,
                        NotificationEventType.SCORE_CHANGE_COMMENT_CREATED,
                        42),
                new NotificationMessage(
                        SECOND_INSTALLATION_ID,
                        NotificationEventType.SCORE_CHANGE_COMMENT_CREATED,
                        42),
                new NotificationMessage(
                        FIRST_INSTALLATION_ID,
                        NotificationEventType.DIARY_ENTRY_COMMENT_CREATED,
                        51),
                new NotificationMessage(
                        SECOND_INSTALLATION_ID,
                        NotificationEventType.DIARY_ENTRY_COMMENT_CREATED,
                        51));
        assertThat(NotificationMessage.class.getRecordComponents())
                .extracting(component -> component.getName())
                .containsExactly("targetFid", "eventType", "resourceId");
    }

    @Test
    void deletesAnInvalidTargetAndContinuesWithTheNextFid() {
        when(fids.findAllByParticipantIdOrderByIdAsc(2L)).thenReturn(List.of(
                target(FIRST_FID),
                target(SECOND_FID)));
        sender.invalidFid = FIRST_FID;

        listener.relationshipScoreChanged(new RelationshipScoreChanged(2, 41));

        verify(fids).deleteByFid(FIRST_FID);
        assertThat(sender.messages)
                .extracting(message -> message.targetFid().value())
                .containsExactly(FIRST_FID, SECOND_FID);
    }

    @Test
    void deletesAMalformedPersistedFidInsteadOfPoisoningThePublication() {
        when(fids.findAllByParticipantIdOrderByIdAsc(2L)).thenReturn(List.of(
                target("malformed"),
                target(SECOND_FID)));

        listener.relationshipScoreChanged(new RelationshipScoreChanged(2, 41));

        verify(fids).deleteByFid("malformed");
        assertThat(sender.messages)
                .extracting(message -> message.targetFid().value())
                .containsExactly(SECOND_FID);
    }

    @Test
    void propagatesTransientDeliveryFailureWithoutDeletingTheFid() {
        when(fids.findAllByParticipantIdOrderByIdAsc(2L))
                .thenReturn(List.of(target(FIRST_FID)));
        sender.transientFid = FIRST_FID;

        assertThatThrownBy(() -> listener.relationshipScoreChanged(
                        new RelationshipScoreChanged(2, 41)))
                .isInstanceOf(NotificationDeliveryException.class);

        verify(fids, never()).deleteByFid(FIRST_FID);
    }

    @Test
    void completesWithoutCallingTheProviderWhenThereIsNoFid() {
        when(fids.findAllByParticipantIdOrderByIdAsc(2L)).thenReturn(List.of());

        listener.diaryEntryCommentCreated(new DiaryEntryCommentCreated(2, 51));

        assertThat(sender.messages).isEmpty();
    }

    @Test
    void fixesListenerIdsAndKeepsPersistedEventsIdentifierOnly() throws Exception {
        assertListenerId(
                "relationshipScoreChanged",
                RelationshipScoreChanged.class,
                NotificationEventListener.RELATIONSHIP_SCORE_CHANGED_LISTENER);
        assertListenerId(
                "scoreChangeCommentCreated",
                ScoreChangeCommentCreated.class,
                NotificationEventListener.SCORE_CHANGE_COMMENT_CREATED_LISTENER);
        assertListenerId(
                "diaryEntryCommentCreated",
                DiaryEntryCommentCreated.class,
                NotificationEventListener.DIARY_ENTRY_COMMENT_CREATED_LISTENER);

        assertThat(RelationshipScoreChanged.class.getRecordComponents())
                .extracting(component -> component.getName())
                .containsExactly("recipientParticipantId", "scoreChangeId");
        assertThat(ScoreChangeCommentCreated.class.getRecordComponents())
                .extracting(component -> component.getName())
                .containsExactly("recipientParticipantId", "scoreChangeId");
        assertThat(DiaryEntryCommentCreated.class.getRecordComponents())
                .extracting(component -> component.getName())
                .containsExactly("recipientParticipantId", "diaryEntryId");
    }

    private void assertListenerId(
            String methodName,
            Class<?> eventType,
            String expectedId) throws Exception {
        Method method = NotificationEventListener.class.getDeclaredMethod(methodName, eventType);
        assertThat(method.getAnnotation(ApplicationModuleListener.class).id())
                .isEqualTo(expectedId);
    }

    private NotificationFid target(String fid) {
        return new NotificationFid(2, fid, Instant.parse("2026-07-21T00:00:00Z"));
    }

    private static final class RecordingSender implements NotificationSender {

        private final List<NotificationMessage> messages = new ArrayList<>();
        private String invalidFid;
        private String transientFid;

        @Override
        public void send(NotificationMessage message) {
            messages.add(message);
            if (message.targetFid().value().equals(invalidFid)) {
                throw new InvalidNotificationTargetException();
            }
            if (message.targetFid().value().equals(transientFid)) {
                throw new NotificationDeliveryException();
            }
        }
    }
}
