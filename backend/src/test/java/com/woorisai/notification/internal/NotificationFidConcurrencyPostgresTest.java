package com.woorisai.notification.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.testing.WoorisaiPostgresContainer;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.persistence.autoconfigure.EntityScan;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import org.testcontainers.postgresql.PostgreSQLContainer;

@Tag("postgres")
@ExtendWith(OutputCaptureExtension.class)
@SpringBootTest(
        classes = NotificationFidConcurrencyPostgresTest.TestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@TestPropertySource(properties = {
        "spring.autoconfigure.exclude="
                + "org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration,"
                + "org.springframework.modulith.events.jpa.JpaEventPublicationAutoConfiguration,"
                + "org.springframework.modulith.events.config.EventPublicationAutoConfiguration",
        "spring.flyway.enabled=true",
        "spring.flyway.locations=classpath:db/migration/postgresql",
        "spring.flyway.default-schema=woorisai",
        "spring.flyway.schemas=woorisai",
        "spring.flyway.create-schemas=true",
        "spring.flyway.baseline-on-migrate=false",
        "spring.jpa.generate-ddl=false",
        "spring.jpa.hibernate.ddl-auto=validate",
        "spring.jpa.properties.hibernate.default_schema=woorisai",
        "spring.jpa.open-in-view=false",
        "spring.sql.init.mode=never",
        "logging.level.org.hibernate.SQL=DEBUG",
        "logging.level.org.springframework.orm.jpa=DEBUG"
})
class NotificationFidConcurrencyPostgresTest {

    private static final long FIRST = 3_000_000_001L;
    private static final long SECOND = 3_000_000_002L;
    private static final String FID = "c123456789012345678901";
    private static final FirebaseInstallationId INSTALLATION_ID =
            FirebaseInstallationId.parse(FID);

    @Autowired
    private NotificationFidService notificationFids;

    @Autowired
    private UpsertCoordination coordination;

    @Autowired
    private JdbcTemplate jdbc;

    @BeforeEach
    void resetDatabase() {
        coordination.reset();
        jdbc.update("DELETE FROM woorisai.notification_fid");
        jdbc.update("DELETE FROM woorisai.participant");
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, 1, 'Fixture One', CURRENT_TIMESTAMP),
                       (?, 2, 'Fixture Two', CURRENT_TIMESTAMP)
                """, FIRST, SECOND);
    }

    @Test
    void atomicallyRegistersReassignsAndUnregistersOnPostgres(CapturedOutput output) {
        Instant beforeRegistration = Instant.now().minusSeconds(1);

        notificationFids.register(FIRST, INSTALLATION_ID);

        assertThat(count()).isOne();
        assertThat(owner()).isEqualTo(FIRST);
        Instant firstCreatedAt = createdAt();
        assertThat(firstCreatedAt)
                .isBetween(beforeRegistration, Instant.now().plusSeconds(1));

        notificationFids.register(SECOND, INSTALLATION_ID);

        assertThat(count()).isOne();
        assertThat(owner()).isEqualTo(SECOND);
        assertThat(createdAt()).isAfterOrEqualTo(firstCreatedAt);

        notificationFids.unregister(FIRST, INSTALLATION_ID);
        assertThat(count()).isOne();
        notificationFids.unregister(SECOND, INSTALLATION_ID);
        assertThat(count()).isZero();

        assertThatThrownBy(() -> jdbc.update("""
                        INSERT INTO woorisai.notification_fid (
                            participant_id, fid, created_at
                        ) VALUES (?, 'malformed', CURRENT_TIMESTAMP)
                        """, FIRST))
                .isInstanceOf(DataIntegrityViolationException.class);
        assertThat(count()).isZero();

        assertLogsRedactFid(output);
    }

    @Test
    void concurrentFirstRegistrationsUseOneAtomicUpsertEach(CapturedOutput output)
            throws Exception {
        coordination.armForTwoUpserts();
        var executor = Executors.newFixedThreadPool(2);

        try {
            var first = executor.submit(() -> notificationFids.register(FIRST, INSTALLATION_ID));
            var second = executor.submit(() -> notificationFids.register(SECOND, INSTALLATION_ID));

            first.get(10, TimeUnit.SECONDS);
            second.get(10, TimeUnit.SECONDS);

            assertThat(coordination.upserts()).isEqualTo(2);
            assertThat(count()).isOne();
            assertThat(owner()).isIn(FIRST, SECOND);
            assertLogsRedactFid(output);
        } finally {
            executor.shutdownNow();
            assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
        }
    }

    private long count() {
        return jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.notification_fid WHERE fid = ?",
                Long.class,
                FID);
    }

    private long owner() {
        return jdbc.queryForObject(
                "SELECT participant_id FROM woorisai.notification_fid WHERE fid = ?",
                Long.class,
                FID);
    }

    private Instant createdAt() {
        return jdbc.queryForObject(
                "SELECT created_at FROM woorisai.notification_fid WHERE fid = ?",
                java.time.OffsetDateTime.class,
                FID).toInstant();
    }

    private void assertLogsRedactFid(CapturedOutput output) {
        assertThat(output.getAll())
                .contains("notification_fid")
                .doesNotContain(FID);
    }

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackageClasses = NotificationFid.class)
    @EnableJpaRepositories(basePackageClasses = NotificationFidRepository.class)
    @Import({NotificationFidService.class, PostgresBeans.class, CoordinationBeans.class})
    static class TestApplication {}

    @TestConfiguration(proxyBeanMethods = false)
    static class PostgresBeans {

        @Bean
        @ServiceConnection
        PostgreSQLContainer postgresContainer() {
            return WoorisaiPostgresContainer.create();
        }
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class CoordinationBeans {

        @Bean
        UpsertCoordination upsertCoordination() {
            return new UpsertCoordination();
        }

        @Bean
        Clock notificationClock() {
            return Clock.systemUTC();
        }

        @Bean
        @Primary
        NotificationFidRepository coordinatedNotificationFidRepository(
                @Qualifier("notificationFidRepository") NotificationFidRepository delegate,
                UpsertCoordination coordination) {
            return new CoordinatedRepository(delegate, coordination);
        }
    }

    static final class UpsertCoordination {

        private final AtomicInteger upserts = new AtomicInteger();
        private volatile CyclicBarrier barrier;

        void reset() {
            upserts.set(0);
            barrier = null;
        }

        void armForTwoUpserts() {
            barrier = new CyclicBarrier(2);
        }

        void beforeUpsert() {
            CyclicBarrier current = barrier;
            if (current == null) {
                return;
            }
            upserts.incrementAndGet();
            try {
                current.await(5, TimeUnit.SECONDS);
            } catch (Exception exception) {
                throw new IllegalStateException(
                        "Concurrent registration did not reach both atomic upserts",
                        exception);
            }
        }

        int upserts() {
            return upserts.get();
        }
    }

    private static final class CoordinatedRepository implements NotificationFidRepository {

        private final NotificationFidRepository delegate;
        private final UpsertCoordination coordination;

        private CoordinatedRepository(
                NotificationFidRepository delegate,
                UpsertCoordination coordination) {
            this.delegate = delegate;
            this.coordination = coordination;
        }

        @Override
        public int upsert(long participantId, String fid, Instant createdAt) {
            coordination.beforeUpsert();
            return delegate.upsert(participantId, fid, createdAt);
        }

        @Override
        public List<NotificationFid> findAllByParticipantIdOrderByIdAsc(long participantId) {
            return delegate.findAllByParticipantIdOrderByIdAsc(participantId);
        }

        @Override
        public int deleteByFid(String fid) {
            return delegate.deleteByFid(fid);
        }

        @Override
        public int deleteByFidAndParticipantId(String fid, long participantId) {
            return delegate.deleteByFidAndParticipantId(fid, participantId);
        }
    }
}
