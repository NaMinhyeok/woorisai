package com.woorisai.notification.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;
import com.woorisai.WoorisaiApplication;
import com.woorisai.diary.DiaryEntryCommentCreated;
import com.woorisai.notification.internal.NotificationSender.InvalidNotificationTargetException;
import com.woorisai.notification.internal.NotificationSender.NotificationDeliveryException;
import com.woorisai.notification.internal.NotificationSender.NotificationEventType;
import com.woorisai.notification.internal.NotificationSender.NotificationMessage;
import com.woorisai.relationship.RelationshipScoreChanged;
import jakarta.persistence.EntityManager;
import java.time.Duration;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.locks.LockSupport;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

@SpringBootTest(
        classes = WoorisaiApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@TestPropertySource(
        locations = "classpath:clean-schema-h2.properties",
        properties = {
            "spring.datasource.url=jdbc:h2:mem:notification-publication;"
                + "MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;"
                + "DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE",
})
class NotificationPublicationIntegrationTest {

    private static final long FIRST = 3_000_000_001L;
    private static final long SECOND = 3_000_000_002L;
    private static final String FID = "c123456789012345678901";
    private static final String SECOND_FID = "d123456789012345678901";
    private static final FirebaseInstallationId INSTALLATION_ID =
            FirebaseInstallationId.parse(FID);
    private static final FirebaseInstallationId SECOND_INSTALLATION_ID =
            FirebaseInstallationId.parse(SECOND_FID);

    @Autowired
    private ApplicationEventPublisher events;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @Autowired
    private EntityManager entityManager;

    @Autowired
    private JdbcTemplate jdbc;

    @MockitoBean(name = "disabledNotificationSender")
    private NotificationSender sender;

    @BeforeEach
    void resetDatabase() {
        reset(sender);
        jdbc.update("DELETE FROM woorisai.event_publication");
        jdbc.update("DELETE FROM woorisai.notification_fid");
        jdbc.update("DELETE FROM woorisai.participant");
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, 1, 'Fixture One', CURRENT_TIMESTAMP),
                       (?, 2, 'Fixture Two', CURRENT_TIMESTAMP)
                """, FIRST, SECOND);
    }

    @Test
    void deliversOnlyAfterProducerCommitAndDeletesTheCompletedPublication() throws Exception {
        insertFid(FIRST, FID);
        ListenerTransaction listenerTransaction = new ListenerTransaction();
        doAnswer(invocation -> {
            listenerTransaction.observeCurrentTransaction();
            return null;
        }).when(sender).send(any(NotificationMessage.class));

        publishAndAssertRecordedBeforeCommit(new RelationshipScoreChanged(FIRST, 41));

        assertThat(listenerTransaction.awaitCompletion()).isEqualTo(
                TransactionSynchronization.STATUS_COMMITTED);
        awaitPublicationCount(0);
        verify(sender).send(new NotificationMessage(
                INSTALLATION_ID,
                NotificationEventType.RELATIONSHIP_SCORE_CHANGED,
                41));
    }

    @Test
    void leavesThePublicationOutstandingWhenTransientDeliveryFails() throws Exception {
        assertFailedPublicationRemains(message -> {
            throw new NotificationDeliveryException();
        });
    }

    @Test
    void leavesThePublicationAndFidOutstandingWhenFirebaseRejectsAnInvalidArgument()
            throws Exception {
        FirebaseMessaging messaging = mock(FirebaseMessaging.class);
        FirebaseMessagingException invalidArgument = mock(FirebaseMessagingException.class);
        when(invalidArgument.getMessagingErrorCode())
                .thenReturn(MessagingErrorCode.INVALID_ARGUMENT);
        when(messaging.send(any(Message.class))).thenThrow(invalidArgument);

        assertFailedPublicationRemains(new FirebaseNotificationSender(messaging));

        assertThat(fidCount(FID)).isOne();
    }

    @Test
    void leavesThePublicationOutstandingWhenTheSenderIsDisabled() throws Exception {
        NotificationSender disabledSender = new NotificationConfiguration
                .DisabledFirebaseConfiguration()
                .disabledNotificationSender();
        assertFailedPublicationRemains(disabledSender);
    }

    @Test
    void completesAndDeletesThePublicationWithoutCallingTheSenderWhenThereIsNoFid() {
        publishAndAssertRecordedBeforeCommit(new DiaryEntryCommentCreated(FIRST, 51));

        awaitPublicationCount(0);
        verifyNoInteractions(sender);
    }

    @Test
    void commitsInvalidTargetDeletionAndCompletesAfterTheRemainingTargetSucceeds()
            throws Exception {
        insertFid(FIRST, FID);
        insertFid(FIRST, SECOND_FID);
        ListenerTransaction listenerTransaction = new ListenerTransaction();
        AtomicBoolean observed = new AtomicBoolean();
        doAnswer(invocation -> {
            if (observed.compareAndSet(false, true)) {
                listenerTransaction.observeCurrentTransaction();
            }
            NotificationMessage message = invocation.getArgument(0);
            if (message.targetFid().value().equals(FID)) {
                throw new InvalidNotificationTargetException();
            }
            return null;
        }).when(sender).send(any(NotificationMessage.class));

        publishAndAssertRecordedBeforeCommit(new RelationshipScoreChanged(FIRST, 41));

        assertThat(listenerTransaction.awaitCompletion()).isEqualTo(
                TransactionSynchronization.STATUS_COMMITTED);
        awaitPublicationCount(0);
        assertThat(fidCount(FID)).isZero();
        assertThat(fidCount(SECOND_FID)).isOne();
        verify(sender).send(new NotificationMessage(
                INSTALLATION_ID, NotificationEventType.RELATIONSHIP_SCORE_CHANGED, 41));
        verify(sender).send(new NotificationMessage(
                SECOND_INSTALLATION_ID,
                NotificationEventType.RELATIONSHIP_SCORE_CHANGED,
                41));
    }

    @Test
    void rollsBackInvalidTargetDeletionWhenALaterTargetFailsTransiently()
            throws Exception {
        insertFid(FIRST, FID);
        insertFid(FIRST, SECOND_FID);
        ListenerTransaction listenerTransaction = new ListenerTransaction();
        AtomicBoolean observed = new AtomicBoolean();
        doAnswer(invocation -> {
            if (observed.compareAndSet(false, true)) {
                listenerTransaction.observeCurrentTransaction();
            }
            NotificationMessage message = invocation.getArgument(0);
            if (message.targetFid().value().equals(FID)) {
                throw new InvalidNotificationTargetException();
            }
            throw new NotificationDeliveryException();
        }).when(sender).send(any(NotificationMessage.class));

        publishAndAssertRecordedBeforeCommit(new RelationshipScoreChanged(FIRST, 41));

        assertThat(listenerTransaction.awaitCompletion()).isEqualTo(
                TransactionSynchronization.STATUS_ROLLED_BACK);
        assertThat(publicationCount()).isOne();
        assertThat(fidCount(FID)).isOne();
        assertThat(fidCount(SECOND_FID)).isOne();
    }

    private void assertFailedPublicationRemains(NotificationSender failingSender) throws Exception {
        insertFid(FIRST, FID);
        ListenerTransaction listenerTransaction = new ListenerTransaction();
        doAnswer(invocation -> {
            listenerTransaction.observeCurrentTransaction();
            failingSender.send(invocation.getArgument(0));
            return null;
        }).when(sender).send(any(NotificationMessage.class));

        publishAndAssertRecordedBeforeCommit(new RelationshipScoreChanged(FIRST, 41));

        assertThat(listenerTransaction.awaitCompletion()).isEqualTo(
                TransactionSynchronization.STATUS_ROLLED_BACK);
        assertThat(publicationCount()).isOne();
        assertThat(jdbc.queryForObject(
                "SELECT listener_id FROM woorisai.event_publication",
                String.class)).isEqualTo(
                        NotificationEventListener.RELATIONSHIP_SCORE_CHANGED_LISTENER);
        assertThat(jdbc.queryForObject(
                "SELECT completion_date IS NULL FROM woorisai.event_publication",
                Boolean.class)).isTrue();
        verify(sender).send(new NotificationMessage(
                INSTALLATION_ID,
                NotificationEventType.RELATIONSHIP_SCORE_CHANGED,
                41));
    }

    private void publishAndAssertRecordedBeforeCommit(Object event) {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            events.publishEvent(event);
            entityManager.flush();

            assertThat(publicationCount()).isOne();
            verifyNoInteractions(sender);
        });
    }

    private void insertFid(long participantId, String fid) {
        jdbc.update("""
                INSERT INTO woorisai.notification_fid (participant_id, fid, created_at)
                VALUES (?, ?, CURRENT_TIMESTAMP)
                """, participantId, fid);
    }

    private int publicationCount() {
        return jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.event_publication",
                Integer.class);
    }

    private int fidCount(String fid) {
        return jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.notification_fid WHERE fid = ?",
                Integer.class,
                fid);
    }

    private void awaitPublicationCount(int expected) {
        long deadline = System.nanoTime() + Duration.ofSeconds(5).toNanos();
        int actual;
        do {
            actual = publicationCount();
            if (actual == expected) {
                return;
            }
            LockSupport.parkNanos(Duration.ofMillis(10).toNanos());
        } while (System.nanoTime() < deadline);
        assertThat(actual).isEqualTo(expected);
    }

    private static final class ListenerTransaction {

        private final CountDownLatch completed = new CountDownLatch(1);
        private final AtomicInteger completionStatus = new AtomicInteger(-1);

        void observeCurrentTransaction() {
            if (!TransactionSynchronizationManager.isActualTransactionActive()) {
                throw new AssertionError("Notification listener must run in a transaction");
            }
            TransactionSynchronizationManager.registerSynchronization(
                    new TransactionSynchronization() {
                        @Override
                        public void afterCompletion(int status) {
                            completionStatus.set(status);
                            completed.countDown();
                        }
                    });
        }

        int awaitCompletion() throws InterruptedException {
            assertThat(completed.await(5, TimeUnit.SECONDS)).isTrue();
            return completionStatus.get();
        }
    }
}
