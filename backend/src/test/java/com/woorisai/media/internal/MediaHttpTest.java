package com.woorisai.media.internal;

import static org.hamcrest.Matchers.aMapWithSize;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.then;
import static org.mockito.Mockito.mock;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.woorisai.media.MediaKind;
import java.net.URI;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.converter.json.JacksonJsonHttpMessageConverter;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.method.annotation.AuthenticationPrincipalArgumentResolver;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import tools.jackson.databind.DeserializationFeature;
import tools.jackson.databind.MapperFeature;
import tools.jackson.databind.json.JsonMapper;

class MediaHttpTest {

    private static final long ACTOR_ID = 3_000_000_001L;
    private static final UUID UPLOAD_ID =
            UUID.fromString("11111111-1111-4111-8111-111111111111");
    private static final Instant EXPIRES_AT = Instant.parse("2026-07-21T00:15:00Z");

    private MediaService media;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        SecurityContextHolder.getContext().setAuthentication(
                UsernamePasswordAuthenticationToken.authenticated(ACTOR_ID, null, List.of()));
        media = mock(MediaService.class);
        mvc = MockMvcBuilders.standaloneSetup(
                        new MediaUploadController(Optional.of(media)),
                        new MediaAttachmentDownloadController(Optional.of(media)))
                .setControllerAdvice(
                        new MediaUploadApiExceptionHandler(),
                        new MediaAttachmentDownloadApiExceptionHandler())
                .setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver())
                .setMessageConverters(new JacksonJsonHttpMessageConverter(
                        JsonMapper.builder()
                                .enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
                                .disable(DeserializationFeature.ACCEPT_FLOAT_AS_INT)
                                .disable(MapperFeature.ALLOW_COERCION_OF_SCALARS)))
                .build();
    }

    @AfterEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void initiatesACommentUploadWithoutAParentIdentifier() throws Exception {
        given(media.initiate(
                        ACTOR_ID,
                        MediaPurpose.SCORE_CHANGE_COMMENT,
                        MediaKind.IMAGE,
                        "reply.png",
                        "image/png",
                        512))
                .willReturn(new InitiatedMediaUpload(
                        UPLOAD_ID,
                        URI.create("https://uploads.example.test/pending/" + UPLOAD_ID),
                        "image/png",
                        EXPIRES_AT));

        mvc.perform(post("/api/v2/media-uploads")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "purpose": "comment",
                                  "kind": "image",
                                  "fileName": "reply.png",
                                  "contentType": "image/png",
                                  "byteSize": 512
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$", aMapWithSize(4)))
                .andExpect(jsonPath("$.uploadId").value(UPLOAD_ID.toString()))
                .andExpect(jsonPath("$.uploadUrl").value(
                        "https://uploads.example.test/pending/" + UPLOAD_ID))
                .andExpect(jsonPath("$.requiredHeaders", aMapWithSize(2)))
                .andExpect(jsonPath("$.requiredHeaders['Content-Type']").value("image/png"))
                .andExpect(jsonPath("$.requiredHeaders['Cache-Control']")
                        .value("private, no-store, max-age=0"))
                .andExpect(jsonPath("$.expiresAt").value(EXPIRES_AT.toString()));

        then(media).should().initiate(
                ACTOR_ID,
                MediaPurpose.SCORE_CHANGE_COMMENT,
                MediaKind.IMAGE,
                "reply.png",
                "image/png",
                512);
    }

    @Test
    void rejectsTheRemovedParentFieldAndScoreVideoBeforeCallingMedia() throws Exception {
        mvc.perform(post("/api/v2/media-uploads")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "purpose": "comment",
                                  "kind": "image",
                                  "fileName": "reply.png",
                                  "contentType": "image/png",
                                  "byteSize": 512,
                                  "scoreChangeId": 20
                                }
                                """))
                .andExpect(status().isBadRequest());

        mvc.perform(post("/api/v2/media-uploads")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "purpose": "scoreChange",
                                  "kind": "video",
                                  "fileName": "score.mp4",
                                  "contentType": "video/mp4",
                                  "byteSize": 512
                                }
                                """))
                .andExpect(status().isBadRequest());

        then(media).shouldHaveNoInteractions();
    }

    @Test
    void completesDiscardsAndDownloadsWithOnlyTheAuthenticatedActorId() throws Exception {
        given(media.complete(ACTOR_ID, UPLOAD_ID)).willReturn(
                new CompletedMediaUpload(
                        UPLOAD_ID, MediaKind.IMAGE, "photo.png", "image/png", 512));
        given(media.download(ACTOR_ID, UPLOAD_ID)).willReturn(
                new MediaDownloadGrant(
                        URI.create("https://downloads.example.test/media/" + UPLOAD_ID
                                + "?signature=redacted"),
                        EXPIRES_AT));

        mvc.perform(post("/api/v2/media-uploads/{id}/complete", UPLOAD_ID))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$", aMapWithSize(5)))
                .andExpect(jsonPath("$.uploadId").value(UPLOAD_ID.toString()))
                .andExpect(jsonPath("$.kind").value("image"))
                .andExpect(jsonPath("$.fileName").value("photo.png"))
                .andExpect(jsonPath("$.contentType").value("image/png"))
                .andExpect(jsonPath("$.byteSize").value(512));
        mvc.perform(delete("/api/v2/media-uploads/{id}", UPLOAD_ID))
                .andExpect(status().isNoContent())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"));
        mvc.perform(get(
                        "/api/v2/media-attachments/{id}/download-url", UPLOAD_ID))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$", aMapWithSize(2)))
                .andExpect(jsonPath("$.downloadUrl").value(
                        "https://downloads.example.test/media/" + UPLOAD_ID
                                + "?signature=redacted"))
                .andExpect(jsonPath("$.expiresAt").value(EXPIRES_AT.toString()));

        then(media).should().complete(ACTOR_ID, UPLOAD_ID);
        then(media).should().discard(ACTOR_ID, UPLOAD_ID);
        then(media).should().download(ACTOR_ID, UPLOAD_ID);
    }

    @Test
    void preservesTheExistingUnavailableHttpProblems() throws Exception {
        given(media.complete(ACTOR_ID, UPLOAD_ID))
                .willThrow(new MediaUploadCompletionUnavailableException());
        given(media.download(ACTOR_ID, UPLOAD_ID))
                .willThrow(new MediaDownloadUnavailableException());

        mvc.perform(post("/api/v2/media-uploads/{id}/complete", UPLOAD_ID))
                .andExpect(status().isServiceUnavailable())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.title").value("Media uploads unavailable"))
                .andExpect(jsonPath("$.status").value(503))
                .andExpect(jsonPath("$.detail")
                        .value("Media uploads are temporarily unavailable."))
                .andExpect(jsonPath("$.instance")
                        .value("/api/v2/media-uploads/" + UPLOAD_ID + "/complete"))
                .andExpect(jsonPath("$.errorCode").value("MEDIA_UPLOADS_UNAVAILABLE"));

        mvc.perform(get("/api/v2/media-attachments/{id}/download-url", UPLOAD_ID))
                .andExpect(status().isServiceUnavailable())
                .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.title").value("Media download unavailable"))
                .andExpect(jsonPath("$.status").value(503))
                .andExpect(jsonPath("$.detail")
                        .value("Media download is temporarily unavailable."))
                .andExpect(jsonPath("$.instance")
                        .value("/api/v2/media-attachments/" + UPLOAD_ID + "/download-url"))
                .andExpect(jsonPath("$.errorCode").value("MEDIA_DOWNLOAD_UNAVAILABLE"));
    }
}
