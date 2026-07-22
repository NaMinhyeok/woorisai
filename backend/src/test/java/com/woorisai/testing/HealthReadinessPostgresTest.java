package com.woorisai.testing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.woorisai.WoorisaiApplication;
import java.time.Duration;
import java.util.concurrent.locks.LockSupport;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.postgresql.PostgreSQLContainer;

@Tag("postgres")
@SpringBootTest(classes = WoorisaiApplication.class)
@AutoConfigureMockMvc
@Import(HealthReadinessPostgresTest.PostgresBeans.class)
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@TestPropertySource(properties = {
        "spring.flyway.locations=classpath:db/migration/postgresql",
        "spring.datasource.hikari.connection-timeout=1000",
        "spring.datasource.hikari.validation-timeout=500",
        "woorisai.media.enabled=false",
        "woorisai.notification.firebase.enabled=false"
})
class HealthReadinessPostgresTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private PostgreSQLContainer postgres;

    @Test
    void returnsServiceUnavailableWhenTheReadinessDatabaseIsDown() throws Exception {
        mvc.perform(get("/health"))
                .andExpect(status().isOk())
                .andExpect(header().string(
                        HttpHeaders.CACHE_CONTROL,
                        containsString("no-store")));

        postgres.stop();

        long deadline = System.nanoTime() + Duration.ofSeconds(10).toNanos();
        int status = -1;
        do {
            status = mvc.perform(get("/health")).andReturn().getResponse().getStatus();
            if (status == 503) {
                break;
            }
            LockSupport.parkNanos(Duration.ofMillis(100).toNanos());
        } while (System.nanoTime() < deadline);

        assertThat(status).isEqualTo(503);
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class PostgresBeans {

        @Bean
        @ServiceConnection
        PostgreSQLContainer postgresContainer() {
            return WoorisaiPostgresContainer.create();
        }
    }
}
