package com.woorisai.notification.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.persistence.autoconfigure.EntityScan;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;

@SpringBootTest(
        classes = NotificationFidCleanSchemaTest.TestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@TestPropertySource(
        locations = "classpath:clean-schema-h2.properties",
        properties = {
            "spring.autoconfigure.exclude="
                + "org.springframework.boot.security.autoconfigure.UserDetailsServiceAutoConfiguration,"
                + "org.springframework.modulith.events.jpa.JpaEventPublicationAutoConfiguration,"
                + "org.springframework.modulith.events.config.EventPublicationAutoConfiguration",
            "spring.datasource.url=jdbc:h2:mem:notification-clean-schema;"
                + "MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;"
                + "DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE"
})
class NotificationFidCleanSchemaTest {

    private static final long FIRST = 3_000_000_001L;
    private static final long SECOND = 3_000_000_002L;
    private static final String FID = "c123456789012345678901";
    private static final FirebaseInstallationId INSTALLATION_ID =
            FirebaseInstallationId.parse(FID);

    @Autowired
    private NotificationFidService notificationFids;

    @Autowired
    private NotificationFidRepository repository;

    @Autowired
    private JdbcTemplate jdbc;

    @BeforeEach
    void resetDatabase() {
        jdbc.update("DELETE FROM woorisai.notification_fid");
        jdbc.update("DELETE FROM woorisai.participant");
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, 1, 'Fixture One', CURRENT_TIMESTAMP),
                       (?, 2, 'Fixture Two', CURRENT_TIMESTAMP)
                """, FIRST, SECOND);
    }

    @Test
    void mapsTheCleanEntityAndOnlyLetsTheCurrentOwnerUnregister() {
        Instant createdAt = Instant.parse("2026-07-21T00:00:00Z");
        jdbc.update("""
                INSERT INTO woorisai.notification_fid (participant_id, fid, created_at)
                VALUES (?, ?, ?)
                """, SECOND, FID, createdAt);

        List<NotificationFid> mapped =
                repository.findAllByParticipantIdOrderByIdAsc(SECOND);
        assertThat(mapped).hasSize(1);
        assertThat(mapped.getFirst().getId()).isPositive();
        assertThat(mapped.getFirst().getParticipantId()).isEqualTo(SECOND);
        assertThat(mapped.getFirst().getFid()).isEqualTo(FID);
        assertThat(mapped.getFirst().getCreatedAt()).isEqualTo(createdAt);

        notificationFids.unregister(FIRST, INSTALLATION_ID);
        notificationFids.unregister(
                FIRST, FirebaseInstallationId.parse("d123456789012345678901"));

        assertThat(countFids()).isOne();

        notificationFids.unregister(SECOND, INSTALLATION_ID);

        assertThat(countFids()).isZero();
    }

    @Test
    void cleanSchemaRejectsMalformedFidsInsertedOutsideTheHttpAdapter() {
        assertThatThrownBy(() -> jdbc.update("""
                        INSERT INTO woorisai.notification_fid (
                            participant_id, fid, created_at
                        ) VALUES (?, ?, CURRENT_TIMESTAMP)
                        """, FIRST, "malformed"))
                .isInstanceOf(DataIntegrityViolationException.class);

        assertThat(countFids()).isZero();
    }

    private long countFids() {
        return jdbc.queryForObject(
                "SELECT COUNT(*) FROM woorisai.notification_fid",
                Long.class);
    }

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackageClasses = NotificationFid.class)
    @EnableJpaRepositories(basePackageClasses = NotificationFidRepository.class)
    @Import({NotificationFidService.class, ClockConfiguration.class})
    static class TestApplication {}

    @TestConfiguration(proxyBeanMethods = false)
    static class ClockConfiguration {

        @Bean
        Clock notificationClock() {
            return Clock.systemUTC();
        }
    }
}
