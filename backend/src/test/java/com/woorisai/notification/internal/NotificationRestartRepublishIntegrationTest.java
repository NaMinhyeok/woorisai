package com.woorisai.notification.internal;

import static org.assertj.core.api.Assertions.assertThat;

import com.woorisai.WoorisaiApplication;
import com.woorisai.notification.internal.NotificationSender.NotificationDeliveryException;
import com.woorisai.notification.internal.NotificationSender.NotificationEventType;
import com.woorisai.notification.internal.NotificationSender.NotificationMessage;
import com.woorisai.relationship.RelationshipScoreChanged;
import jakarta.persistence.EntityManager;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.locks.LockSupport;
import org.junit.jupiter.api.MethodOrderer.OrderAnnotation;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.TestPropertySource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@SpringBootTest(
        classes = WoorisaiApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@Import(NotificationRestartRepublishIntegrationTest.RecordingSenderConfiguration.class)
@TestMethodOrder(OrderAnnotation.class)
@TestPropertySource(
        locations = "classpath:clean-schema-h2.properties",
        properties = {
            "spring.datasource.url=jdbc:h2:mem:notification-restart-republish;"
                + "MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;"
                + "DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE",
})
class NotificationRestartRepublishIntegrationTest {

    private static final long FIRST = 3_000_000_001L;
    private static final String FID = "c123456789012345678901";
    private static final NotificationMessage EXPECTED = new NotificationMessage(
            FirebaseInstallationId.parse(FID),
            NotificationEventType.RELATIONSHIP_SCORE_CHANGED,
            41);

    @Autowired
    private ApplicationEventPublisher events;

    @Autowired
    private PlatformTransactionManager transactionManager;

    @Autowired
    private EntityManager entityManager;

    @Autowired
    private JdbcTemplate jdbc;

    @Test
    @Order(1)
    @DirtiesContext(methodMode = DirtiesContext.MethodMode.AFTER_METHOD)
    void leavesASerializedPublicationOutstandingBeforeTheColdRestart() {
        RecordingState.reset(1);
        jdbc.update("DELETE FROM woorisai.event_publication");
        jdbc.update("DELETE FROM woorisai.notification_fid");
        jdbc.update("DELETE FROM woorisai.participant");
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, 1, 'Fixture One', CURRENT_TIMESTAMP),
                       (?, 2, 'Fixture Two', CURRENT_TIMESTAMP)
                """, FIRST, FIRST + 1);
        jdbc.update("""
                INSERT INTO woorisai.notification_fid (participant_id, fid, created_at)
                VALUES (?, ?, CURRENT_TIMESTAMP)
                """, FIRST, FID);

        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            events.publishEvent(new RelationshipScoreChanged(FIRST, 41));
            entityManager.flush();
        });

        awaitRecordedMessages(1);
        awaitPublicationCount(1);
        assertThat(jdbc.queryForObject(
                "SELECT listener_id FROM woorisai.event_publication",
                String.class)).isEqualTo(
                        NotificationEventListener.RELATIONSHIP_SCORE_CHANGED_LISTENER);
        assertThat(RecordingState.messages()).containsExactly(EXPECTED);
    }

    @Test
    @Order(2)
    void republishesAndDeletesThePersistedPublicationInTheNewContext() {
        awaitRecordedMessages(2);
        awaitPublicationCount(0);

        assertThat(RecordingState.messages()).containsExactly(EXPECTED, EXPECTED);
    }

    private void awaitPublicationCount(int expected) {
        long deadline = System.nanoTime() + Duration.ofSeconds(5).toNanos();
        int actual;
        do {
            actual = jdbc.queryForObject(
                    "SELECT COUNT(*) FROM woorisai.event_publication",
                    Integer.class);
            if (actual == expected) {
                return;
            }
            LockSupport.parkNanos(Duration.ofMillis(10).toNanos());
        } while (System.nanoTime() < deadline);
        assertThat(actual).isEqualTo(expected);
    }

    private static void awaitRecordedMessages(int expected) {
        long deadline = System.nanoTime() + Duration.ofSeconds(5).toNanos();
        while (RecordingState.messages().size() != expected
                && System.nanoTime() < deadline) {
            LockSupport.parkNanos(Duration.ofMillis(10).toNanos());
        }
        assertThat(RecordingState.messages()).hasSize(expected);
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class RecordingSenderConfiguration {

        @Bean
        @Primary
        NotificationSender recordingNotificationSender() {
            return message -> {
                RecordingState.record(message);
                if (RecordingState.consumeFailure()) {
                    throw new NotificationDeliveryException();
                }
            };
        }
    }

    private static final class RecordingState {

        private static final CopyOnWriteArrayList<NotificationMessage> MESSAGES =
                new CopyOnWriteArrayList<>();
        private static final AtomicInteger FAILURES = new AtomicInteger();

        static void reset(int failures) {
            MESSAGES.clear();
            FAILURES.set(failures);
        }

        static void record(NotificationMessage message) {
            MESSAGES.add(message);
        }

        static boolean consumeFailure() {
            return FAILURES.getAndUpdate(current -> Math.max(0, current - 1)) > 0;
        }

        static List<NotificationMessage> messages() {
            return List.copyOf(MESSAGES);
        }
    }
}
