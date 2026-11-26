package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.woorisai.WoorisaiApplication;
import java.time.OffsetDateTime;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(classes = WoorisaiApplication.class)
@AutoConfigureMockMvc
@Import(MediaCleanSchemaH2Test.TestBeans.class)
@TestPropertySource(locations = "classpath:clean-schema-h2.properties", properties = {
    "spring.datasource.url=jdbc:h2:mem:diary-attachment-workflow;"
        + "MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE"
})
class DiaryAttachmentDownloadWorkflowTest {

    @Autowired private MockMvc mvc;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private PasswordEncoder passwordEncoder;

    @Test
    void deletingTheDiaryStopsNewDownloadGrantsButKeepsTheAttachmentLink() throws Exception {
        UUID attachment = UUID.fromString("20000000-0000-4000-8000-000000000002");
        OffsetDateTime createdAt = OffsetDateTime.parse("2026-07-21T00:00:00Z");
        jdbc.update("""
                INSERT INTO woorisai.participant (id, slot, display_name, created_at)
                VALUES (1, 1, 'One', ?), (2, 2, 'Two', ?)
                """, createdAt, createdAt);
        jdbc.update("""
                INSERT INTO woorisai.participant_credential (participant_id, pin_hash, updated_at)
                VALUES (1, ?, ?), (2, ?, ?)
                """, passwordEncoder.encode("0123"), createdAt,
                passwordEncoder.encode("0123"), createdAt);
        jdbc.update("""
                INSERT INTO woorisai.diary_entry (id, author_id, content, created_at)
                VALUES (40, 1, 'fixture diary', ?)
                """, createdAt);
        jdbc.update("""
                INSERT INTO woorisai.media_attachment (
                    id, uploader_id, diary_entry_id, purpose, kind, status, object_key,
                    original_name, content_type, expected_size, actual_size, position, created_at, ready_at)
                VALUES (?, 1, 40, 'DIARY_ENTRY', 'IMAGE', 'READY', 'media/fixture',
                        'fixture.png', 'image/png', 8, 8, 0, ?, ?)
                """, attachment, createdAt, createdAt);
        var partnerDownload = get("/api/v2/media-attachments/{id}/download-url", attachment)
                .headers(authorization("2"));

        mvc.perform(partnerDownload).andExpect(status().isOk());
        mvc.perform(delete("/api/v2/diary-entries/40").headers(authorization("1")))
                .andExpect(status().isNoContent());
        mvc.perform(partnerDownload).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.errorCode").value("MEDIA_ATTACHMENT_NOT_FOUND"));
        assertThat(jdbc.queryForObject("""
                SELECT COUNT(*) FROM woorisai.media_attachment
                WHERE id = ? AND diary_entry_id = 40 AND revoked_at IS NOT NULL
                """, Integer.class, attachment)).isOne();
    }

    private static HttpHeaders authorization(String slot) {
        var headers = new HttpHeaders();
        headers.setBasicAuth(slot, "0123");
        return headers;
    }
}