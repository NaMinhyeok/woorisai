package com.woorisai.diary.internal;

import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.then;
import static org.mockito.BDDMockito.willThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.method.annotation.AuthenticationPrincipalArgumentResolver;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.transaction.CannotCreateTransactionException;

class DiaryControllerTest {

    private static final long ACTOR = 3_000_000_001L;
    private static final UUID UPLOAD_ID =
            UUID.fromString("11111111-1111-4111-8111-111111111111");
    private static final Instant CREATED_AT = Instant.parse("2026-07-21T00:00:00Z");
    private static final Instant UPDATED_AT = Instant.parse("2026-07-21T00:01:00Z");

    private DiaryService diary;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        SecurityContextHolder.getContext().setAuthentication(
                UsernamePasswordAuthenticationToken.authenticated(ACTOR, null, List.of()));
        diary = mock(DiaryService.class);
        mvc = MockMvcBuilders.standaloneSetup(new DiaryController(diary))
                .setControllerAdvice(new DiaryApiExceptionHandler())
                .setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver())
                .build();
    }

    @AfterEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void routesEntryReadsAndWritesWithEndpointSpecificResponses() throws Exception {
        DiaryParticipantResponse author = new DiaryParticipantResponse(1, "Fixture One");
        DiaryMediaResponse media = new DiaryMediaResponse(
                UPLOAD_ID, "IMAGE", "memory.png", "image/png", 512);
        DiaryEntryListItemResponse item = new DiaryEntryListItemResponse(
                41, author, "entry", CREATED_AT, null, true, List.of(media), 1);
        given(diary.listEntries(ACTOR, 2)).willReturn(new DiaryEntryListResponse(
                List.of(item), 2, 20, false, 21));
        given(diary.createEntry(
                        ACTOR,
                        CreateDiaryEntryCommand.from("entry", List.of(UPLOAD_ID))))
                .willReturn(new DiaryEntryCreatedResponse(
                        41, author, "entry", CREATED_AT, null, true, List.of(media), 0));
        given(diary.getEntry(ACTOR, 41)).willReturn(new DiaryEntryDetailResponse(
                41,
                author,
                "entry",
                CREATED_AT,
                null,
                true,
                List.of(media),
                1,
                List.of(new DiaryCommentResponse(
                        51, author, "comment", CREATED_AT, null, true))));
        given(diary.updateEntry(
                        ACTOR,
                        41,
                        UpdateDiaryEntryCommand.from(null, List.of())))
                .willReturn(new DiaryEntryUpdatedResponse(
                        41, author, "entry", CREATED_AT, UPDATED_AT, true, List.of(), 1));

        mvc.perform(get("/api/v2/diary-entries?pageNumber=2"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.pageNumber").value(2))
                .andExpect(jsonPath("$.results[0].id").value(41))
                .andExpect(jsonPath("$.results[0].attachments[0].id")
                        .value(UPLOAD_ID.toString()));
        mvc.perform(post("/api/v2/diary-entries")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "content": "entry",
                                  "mediaUploadIds": ["11111111-1111-4111-8111-111111111111"]
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.id").value(41));
        mvc.perform(get("/api/v2/diary-entries/41"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.comments[0].id").value(51));
        mvc.perform(patch("/api/v2/diary-entries/41")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"mediaUploadIds\":[]}"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.updatedAt").value(UPDATED_AT.toString()));
        mvc.perform(patch("/api/v2/diary-entries/41")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":null,\"mediaUploadIds\":[]}"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.updatedAt").value(UPDATED_AT.toString()));
        mvc.perform(delete("/api/v2/diary-entries/41"))
                .andExpect(status().isNoContent())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"));

        then(diary).should().listEntries(ACTOR, 2);
        then(diary).should().createEntry(
                ACTOR, CreateDiaryEntryCommand.from("entry", List.of(UPLOAD_ID)));
        then(diary).should().getEntry(ACTOR, 41);
        then(diary).should(times(2)).updateEntry(
                ACTOR, 41, UpdateDiaryEntryCommand.from(null, List.of()));
        then(diary).should().deleteEntry(ACTOR, 41);
    }

    @Test
    void routesCommentCreateUpdateAndDeleteByAuthenticatedActor() throws Exception {
        DiaryParticipantResponse author = new DiaryParticipantResponse(1, "Fixture One");
        given(diary.createComment(
                        ACTOR, 41, CreateDiaryCommentCommand.from("comment")))
                .willReturn(new DiaryEntryCommentCreatedResponse(
                        51, author, "comment", CREATED_AT, null, true));
        given(diary.updateComment(
                        ACTOR, 51, UpdateDiaryCommentCommand.from("updated")))
                .willReturn(new DiaryEntryCommentUpdatedResponse(
                        51, author, "updated", CREATED_AT, UPDATED_AT, true));

        mvc.perform(post("/api/v2/diary-entries/41/comments")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"comment\"}"))
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.id").value(51));
        mvc.perform(patch("/api/v2/diary-entry-comments/51")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"updated\"}"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.content").value("updated"));
        mvc.perform(delete("/api/v2/diary-entry-comments/51"))
                .andExpect(status().isNoContent())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"));

        then(diary).should().createComment(
                ACTOR, 41, CreateDiaryCommentCommand.from("comment"));
        then(diary).should().updateComment(
                ACTOR, 51, UpdateDiaryCommentCommand.from("updated"));
        then(diary).should().deleteComment(ACTOR, 51);
    }

    @Test
    void normalizesMalformedAndUnavailableRequestsWithoutCachingDetails() throws Exception {
        mvc.perform(get("/api/v2/diary-entries?pageNumber=not-a-number"))
                .andExpect(status().isBadRequest())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("INVALID_DIARY_REQUEST"));

        given(diary.listEntries(ACTOR, 1)).willThrow(
                new CannotCreateTransactionException("fixture transaction unavailable"));

        mvc.perform(get("/api/v2/diary-entries"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("DIARY_UNAVAILABLE"));
    }

    @Test
    void rejectsPrimitiveAndPatchMeaningAtTheWebCommandBoundary() throws Exception {
        mvc.perform(get("/api/v2/diary-entries?pageNumber=0"))
                .andExpect(status().isBadRequest())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("INVALID_DIARY_REQUEST"));
        mvc.perform(get("/api/v2/diary-entries/0"))
                .andExpect(status().isBadRequest())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("INVALID_DIARY_REQUEST"));
        mvc.perform(patch("/api/v2/diary-entries/41")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("INVALID_DIARY_REQUEST"));
        mvc.perform(post("/api/v2/diary-entries/41/comments")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"   \"}"))
                .andExpect(status().isBadRequest())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("INVALID_DIARY_REQUEST"));

        then(diary).shouldHaveNoInteractions();
    }

    @Test
    void mapsDiaryOwnershipAndMissingResourcesToStableProblems() throws Exception {
        given(diary.getEntry(ACTOR, 41)).willThrow(new DiaryEntryNotFoundException());

        mvc.perform(get("/api/v2/diary-entries/41"))
                .andExpect(status().isNotFound())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("DIARY_NOT_FOUND"));

        UpdateDiaryEntryCommand update = UpdateDiaryEntryCommand.from("changed", null);
        given(diary.updateEntry(ACTOR, 41, update))
                .willThrow(new DiaryMutationForbiddenException());

        mvc.perform(patch("/api/v2/diary-entries/41")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"changed\"}"))
                .andExpect(status().isForbidden())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("DIARY_FORBIDDEN"));

        willThrow(new ObjectOptimisticLockingFailureException(DiaryEntry.class, 41L))
                .given(diary)
                .updateEntry(ACTOR, 41, update);

        mvc.perform(patch("/api/v2/diary-entries/41")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"changed\"}"))
                .andExpect(status().isConflict())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("DIARY_CONFLICT"));
    }
}
