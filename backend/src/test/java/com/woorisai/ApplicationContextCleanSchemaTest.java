package com.woorisai;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.emptyString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.ApplicationContext;
import org.springframework.http.HttpHeaders;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(
        locations = "classpath:clean-schema-h2.properties",
        properties = {
            "spring.datasource.url=jdbc:h2:mem:application-clean-schema;"
                + "MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;"
                + "DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE",
})
class ApplicationContextCleanSchemaTest {

    @Autowired
    private MockMvc mvc;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private ApplicationContext context;

    @Test
    void startsTheCompleteApplicationAgainstOnlyTheCleanSchema() {
        assertThat(context.containsBean("eventPublicationRegistry")).isTrue();
        assertThat(jdbc.queryForObject("""
                SELECT COUNT(*)
                FROM information_schema.tables
                WHERE table_schema = 'woorisai'
                  AND table_name = 'event_publication'
                """, Integer.class)).isOne();
        assertThat(jdbc.queryForObject("""
                SELECT COUNT(*)
                FROM information_schema.tables
                WHERE table_name IN ('access_token', 'app_access_token', 'push_device')
                """, Integer.class)).isZero();
    }

    @Test
    void exposesOnlyTheReadinessAndLoginOptionsGetsWithoutBasicCredentials()
            throws Exception {
        mvc.perform(get("/health").header(HttpHeaders.AUTHORIZATION, "Basic !!!"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));

        mvc.perform(get("/api/v2/auth/login-options")
                        .header(HttpHeaders.AUTHORIZATION, "Basic !!!"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(header().doesNotExist(HttpHeaders.WWW_AUTHENTICATE))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, not(emptyString())))
                .andExpect(jsonPath("$.errorCode").value("LOGIN_OPTIONS_UNAVAILABLE"));
    }
}
