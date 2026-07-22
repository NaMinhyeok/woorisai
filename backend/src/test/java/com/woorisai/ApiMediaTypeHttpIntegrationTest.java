package com.woorisai;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;
import java.util.Base64;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(
        locations = "classpath:clean-schema-h2.properties",
        properties = {
            "spring.datasource.url=jdbc:h2:mem:api-media-type-http;"
                + "MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;"
                + "DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE",
        })
class ApiMediaTypeHttpIntegrationTest {

    private static final long FIRST = 3_000_000_001L;
    private static final long SECOND = 3_000_000_002L;
    private static final OffsetDateTime NOW =
            OffsetDateTime.parse("2026-07-21T00:00:00Z");

    @Autowired
    private MockMvc mvc;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @BeforeEach
    void canonicalPairAndCredential() {
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (?, 1, 'Fixture One', ?), (?, 2, 'Fixture Two', ?)
                """, FIRST, NOW, SECOND, NOW);
        jdbc.update("""
                INSERT INTO woorisai.participant_credential (
                    participant_id, pin_hash, updated_at
                ) VALUES (?, ?, ?)
                """, FIRST, passwordEncoder.encode("0123"), NOW);
    }

    @Test
    void rejectsUnsupportedContentTypesAcrossAllJsonBodyOperations() throws Exception {
        List<JsonEndpoint> endpoints = List.of(
                new JsonEndpoint(HttpMethod.POST, "/api/v2/media-uploads"),
                new JsonEndpoint(HttpMethod.POST, "/api/v2/score-changes"),
                new JsonEndpoint(HttpMethod.POST, "/api/v2/score-changes/20/comments"),
                new JsonEndpoint(HttpMethod.POST, "/api/v2/diary-entries"),
                new JsonEndpoint(HttpMethod.PATCH, "/api/v2/diary-entries/40"),
                new JsonEndpoint(HttpMethod.POST, "/api/v2/diary-entries/40/comments"),
                new JsonEndpoint(HttpMethod.PATCH, "/api/v2/diary-entry-comments/50"),
                new JsonEndpoint(HttpMethod.POST, "/api/v2/notification-fids"),
                new JsonEndpoint(HttpMethod.DELETE, "/api/v2/notification-fids"));

        for (JsonEndpoint endpoint : endpoints) {
            mvc.perform(request(endpoint.method(), endpoint.path())
                            .header(HttpHeaders.AUTHORIZATION, basic("1", "0123"))
                            .contentType(MediaType.TEXT_PLAIN)
                            .content("{}"))
                    .andExpect(status().isUnsupportedMediaType())
                    .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                    .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                    .andExpect(jsonPath("$.title").value("Unsupported media type"))
                    .andExpect(jsonPath("$.status").value(415))
                    .andExpect(jsonPath("$.detail")
                            .value("Content-Type must be application/json."))
                    .andExpect(jsonPath("$.instance").value(endpoint.path()))
                    .andExpect(jsonPath("$.errorCode").value("UNSUPPORTED_MEDIA_TYPE"));
        }
    }

    private static String basic(String slot, String pin) {
        return "Basic " + Base64.getEncoder().encodeToString(
                (slot + ":" + pin).getBytes(StandardCharsets.US_ASCII));
    }

    private record JsonEndpoint(HttpMethod method, String path) {}
}
