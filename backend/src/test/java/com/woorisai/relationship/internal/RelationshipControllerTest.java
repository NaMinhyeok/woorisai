package com.woorisai.relationship.internal;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.method.annotation.AuthenticationPrincipalArgumentResolver;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class RelationshipControllerTest {

    private static final long ACTOR = 3_000_000_001L;
    private static final Instant NOW = Instant.parse("2026-07-21T00:00:00Z");

    private RelationshipService service;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        SecurityContextHolder.getContext().setAuthentication(
                UsernamePasswordAuthenticationToken.authenticated(ACTOR, null, List.of()));
        service = mock(RelationshipService.class);
        mvc = MockMvcBuilders.standaloneSetup(new RelationshipController(service))
                .setControllerAdvice(new RelationshipApiExceptionHandler())
                .setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver())
                .build();
    }

    @AfterEach
    void clearSecurityContext() {
        SecurityContextHolder.clearContext();
    }

    @Test
    void servesTheFiveRelationshipEndpointsWithNoStoreResponses() throws Exception {
        ParticipantView self = new ParticipantView(1, "Fixture One", true);
        ParticipantView partner = new ParticipantView(2, "Fixture Two", false);
        RelationshipScoreView outgoing = new RelationshipScoreView(self, partner, 51, NOW);
        RelationshipScoreView incoming = new RelationshipScoreView(partner, self, 70, NOW);
        ScoreChangeView change = new ScoreChangeView(
                20,
                self,
                partner,
                self,
                1,
                51,
                null,
                NOW,
                0,
                List.of());
        ScoreChangeCommentView comment = new ScoreChangeCommentView(
                30, self, "hello", NOW, List.of());

        when(service.relationshipScores(ACTOR)).thenReturn(
                new RelationshipScoresResponse(self, partner, outgoing, incoming));
        when(service.scoreChanges(ACTOR, 1)).thenReturn(new ScoreChangeHistoryResponse(
                List.of(change),
                new ScoreChangeHistoryResponse.Paging(1, 20, false, 1)));
        when(service.changeScore(eq(ACTOR), any(ChangeScoreCommand.class))).thenReturn(
                new ScoreChangeCreatedResponse(change, outgoing));
        when(service.scoreChange(ACTOR, 20)).thenReturn(
                new ScoreChangeThreadResponse(change, List.of(comment)));
        when(service.createComment(
                        eq(ACTOR), eq(20L), any(CreateScoreCommentCommand.class)))
                .thenReturn(new ScoreChangeCommentCreatedResponse(comment));

        mvc.perform(get("/api/v2/relationship-scores"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.self.slot").value(1))
                .andExpect(jsonPath("$.partner.displayName").value("Fixture Two"))
                .andExpect(jsonPath("$.outgoing.currentScore").value(51))
                .andExpect(jsonPath("$.incoming.currentScore").value(70));

        mvc.perform(get("/api/v2/score-changes"))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.results[0].id").value(20))
                .andExpect(jsonPath("$.paging.pageNumber").value(1));

        mvc.perform(post("/api/v2/score-changes")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"delta\":1,\"reason\":\"hello\",\"mediaUploadIds\":[]}"))
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.change.resultingScore").value(51));

        mvc.perform(get("/api/v2/score-changes/20"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.comments[0].content").value("hello"));

        mvc.perform(post("/api/v2/score-changes/20/comments")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"hello\",\"mediaUploadIds\":[]}"))
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.comment.id").value(30));

        verify(service).scoreChanges(ACTOR, 1);
        verify(service).changeScore(
                ACTOR,
                ChangeScoreCommand.from(1, null, "hello", List.of()));
        verify(service).createComment(
                ACTOR,
                20,
                CreateScoreCommentCommand.from("hello", List.of()));
    }

    @Test
    void mapsStableClientAndAvailabilityProblems() throws Exception {
        when(service.changeScore(eq(ACTOR), any(ChangeScoreCommand.class)))
                .thenThrow(new RelationshipConflictException());
        mvc.perform(post("/api/v2/score-changes")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"targetScore\":50}"))
                .andExpect(status().isConflict())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("RELATIONSHIP_CONFLICT"));

        doThrow(new ObjectOptimisticLockingFailureException(RelationshipScore.class, 10L))
                .when(service)
                .changeScore(eq(ACTOR), any(ChangeScoreCommand.class));
        mvc.perform(post("/api/v2/score-changes")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"delta\":1}"))
                .andExpect(status().isConflict())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("RELATIONSHIP_CONFLICT"));

        mvc.perform(get("/api/v2/score-changes?pageNumber=0"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errorCode").value("INVALID_RELATIONSHIP_REQUEST"));

        mvc.perform(post("/api/v2/score-changes")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errorCode").value("INVALID_RELATIONSHIP_REQUEST"));
    }

    @Test
    void rejectsEscapedNulReasonAndCommentAsInvalidRequests() throws Exception {
        mvc.perform(post("/api/v2/score-changes")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"delta":1,"reason":"bad\\u0000reason","mediaUploadIds":[]}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("INVALID_RELATIONSHIP_REQUEST"));

        mvc.perform(post("/api/v2/score-changes/20/comments")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"content":"bad\\u0000comment","mediaUploadIds":[]}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("INVALID_RELATIONSHIP_REQUEST"));

        verifyNoInteractions(service);
    }

    @Test
    void enforcesCrossFieldRulesThatTheGeneratorCompatibleSchemaOnlyDescribes() throws Exception {
        for (String request : List.of(
                "{}",
                "{\"delta\":0}",
                "{\"delta\":1,\"targetScore\":50}")) {
            mvc.perform(post("/api/v2/score-changes")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                    .andExpect(jsonPath("$.errorCode")
                            .value("INVALID_RELATIONSHIP_REQUEST"));
        }

        for (String request : List.of(
                "{}",
                "{\"content\":null,\"mediaUploadIds\":[]}")) {
            mvc.perform(post("/api/v2/score-changes/20/comments")
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(request))
                    .andExpect(status().isBadRequest())
                    .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                    .andExpect(jsonPath("$.errorCode")
                            .value("INVALID_RELATIONSHIP_REQUEST"));
        }

        verifyNoInteractions(service);
    }

    @Test
    void acceptsExplicitNullOptionalFieldsWithoutChangingTheirOmissionSemantics() throws Exception {
        ParticipantView self = new ParticipantView(1, "Fixture One", true);
        ParticipantView partner = new ParticipantView(2, "Fixture Two", false);
        RelationshipScoreView outgoing = new RelationshipScoreView(self, partner, 51, NOW);
        ScoreChangeView change = new ScoreChangeView(
                20,
                self,
                partner,
                self,
                1,
                51,
                null,
                NOW,
                0,
                List.of());
        when(service.changeScore(
                        ACTOR,
                        ChangeScoreCommand.from(1, null, null, null)))
                .thenReturn(new ScoreChangeCreatedResponse(change, outgoing));

        mvc.perform(post("/api/v2/score-changes")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "delta": 1,
                                  "targetScore": null,
                                  "reason": null,
                                  "mediaUploadIds": null
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.change.id").value(20));

        verify(service).changeScore(
                ACTOR,
                ChangeScoreCommand.from(1, null, null, null));
    }

    @Test
    void mapsAnEmptyLaterHistoryPageToNotFound() throws Exception {
        when(service.scoreChanges(ACTOR, 2)).thenThrow(new RelationshipNotFoundException());

        mvc.perform(get("/api/v2/score-changes?pageNumber=2"))
                .andExpect(status().isNotFound())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("RELATIONSHIP_NOT_FOUND"));

        verify(service).scoreChanges(ACTOR, 2);
    }
}
