package com.woorisai.relationship.internal;

import com.woorisai.media.AttachScoreChangeMediaCommand;
import com.woorisai.media.AttachScoreCommentMediaCommand;
import com.woorisai.media.AttachedMedia;
import com.woorisai.media.AttachedMediaQuery;
import com.woorisai.media.AttachedMediaQuery.AttachedMediaUnavailableException;
import com.woorisai.media.AttachedMediaQuery.InvalidAttachedMediaQueryException;
import com.woorisai.media.MediaAttachmentMutation;
import com.woorisai.media.ScoreChangeMediaParent;
import com.woorisai.media.ScoreCommentMediaParent;
import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantDirectory.ParticipantPairUnavailableException;
import com.woorisai.participant.ParticipantReference;
import com.woorisai.relationship.RelationshipScoreChanged;
import com.woorisai.relationship.ScoreChangeCommentCreated;
import com.woorisai.support.paging.PageResponse;
import java.time.Clock;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
class RelationshipService {

    private static final int HISTORY_PAGE_SIZE = 20;

    private final ParticipantDirectory participants;
    private final RelationshipScoreRepository relationshipScores;
    private final ScoreChangeRepository scoreChanges;
    private final ScoreChangeCommentRepository comments;
    private final MediaAttachmentMutation mediaMutation;
    private final AttachedMediaQuery mediaQuery;
    private final ApplicationEventPublisher events;
    private final Clock clock;

    @Transactional(readOnly = true)
    public RelationshipScoresResponse relationshipScores(long actorId) {
        Relationship relationship = relationship(actorId);
        return new RelationshipScoresResponse(
                participant(relationship.self(), relationship),
                participant(relationship.partner(), relationship),
                score(relationship.outgoing(), relationship),
                score(relationship.incoming(), relationship));
    }

    @Transactional(readOnly = true)
    public PageResponse<ScoreChangeView> scoreChanges(
            long actorId,
            int pageNumber) {
        Relationship relationship = relationship(actorId);
        Page<ScoreChange> page = scoreChanges
                .findByRelationshipScoreIdInOrderByCreatedAtDescIdDesc(
                        relationship.scoreIds(),
                        PageRequest.of(pageNumber - 1, HISTORY_PAGE_SIZE));
        if (pageNumber > 1 && page.isEmpty()) {
            throw new RelationshipNotFoundException();
        }
        List<ScoreChange> changes = page.getContent();
        Map<Long, Long> commentCounts = commentCounts(changes);
        Map<Long, List<AttachedMedia>> attachments = scoreMedia(changes);
        return PageResponse.of(page, change -> scoreChange(
                change,
                commentCounts.getOrDefault(change.getId(), 0L),
                media(attachments, change.getId()),
                relationship));
    }

    @Transactional
    public ScoreChangeCreatedResponse changeScore(
            long actorId,
            ChangeScoreCommand command) {
        Relationship relationship = relationship(actorId);
        RelationshipScore outgoing = relationship.outgoing();

        Instant now = Instant.now(clock).truncatedTo(ChronoUnit.MICROS);
        ScoreChange change;
        try {
            change = outgoing.change(command.intent(), command.reason(), now);
        } catch (RelationshipScoreChangeRejectedException exception) {
            throw new RelationshipConflictException(exception);
        }
        try {
            relationshipScores.flush();
        } catch (OptimisticLockingFailureException exception) {
            throw new RelationshipConflictException(exception);
        }
        change = scoreChanges.saveAndFlush(change);
        attachScoreMedia(
                relationship.self().id(),
                change.getId(),
                command.mediaUploadIds());
        Map<Long, List<AttachedMedia>> attachments = scoreMedia(List.of(change));
        ScoreChangeView view = scoreChange(
                change,
                0,
                media(attachments, change.getId()),
                relationship);
        events.publishEvent(new RelationshipScoreChanged(
                relationship.partner().id(), change.getId()));
        return new ScoreChangeCreatedResponse(view, score(outgoing, relationship));
    }

    @Transactional(readOnly = true)
    public ScoreChangeThreadResponse scoreChange(
            long actorId,
            long scoreChangeId) {
        Relationship relationship = relationship(actorId);
        ScoreChange change = ownedScoreChange(scoreChangeId, relationship);
        List<ScoreChangeComment> thread = comments.findByScoreChangeId(scoreChangeId).stream()
                .sorted(ScoreChangeComment.IN_THREAD_ORDER)
                .toList();
        Map<Long, List<AttachedMedia>> changeMedia = scoreMedia(List.of(change));
        Map<Long, List<AttachedMedia>> commentMedia = commentMedia(thread);
        List<ScoreChangeCommentView> commentViews = thread.stream()
                .map(comment -> scoreComment(
                        comment,
                        media(commentMedia, comment.getId()),
                        relationship))
                .toList();
        return new ScoreChangeThreadResponse(
                scoreChange(
                        change,
                        commentViews.size(),
                        media(changeMedia, change.getId()),
                        relationship),
                commentViews);
    }

    @Transactional
    public ScoreChangeCommentCreatedResponse createComment(
            long actorId,
            long scoreChangeId,
            CreateScoreCommentCommand command) {
        Relationship relationship = relationship(actorId);
        ownedScoreChange(scoreChangeId, relationship);

        Instant now = Instant.now(clock).truncatedTo(ChronoUnit.MICROS);
        ScoreChangeComment comment = comments.saveAndFlush(new ScoreChangeComment(
                scoreChangeId,
                relationship.self().id(),
                command.content(),
                now));
        attachCommentMedia(
                relationship.self().id(),
                comment.getId(),
                command.mediaUploadIds());
        Map<Long, List<AttachedMedia>> attachments = commentMedia(List.of(comment));
        ScoreChangeCommentView view = scoreComment(
                comment,
                media(attachments, comment.getId()),
                relationship);
        events.publishEvent(new ScoreChangeCommentCreated(
                relationship.partner().id(), scoreChangeId));
        return new ScoreChangeCommentCreatedResponse(view);
    }

    private Relationship relationship(long actorId) {
        return Relationship.of(actorId, canonicalPair(), scoresInSourceOrder());
    }

    private CanonicalParticipantPair canonicalPair() {
        try {
            return participants.canonicalPair();
        } catch (ParticipantPairUnavailableException exception) {
            throw new RelationshipUnavailableException(exception);
        }
    }

    private List<RelationshipScore> scoresInSourceOrder() {
        return relationshipScores.findAllByOrderBySourceParticipantIdAsc();
    }

    private ScoreChange ownedScoreChange(long scoreChangeId, Relationship relationship) {
        ScoreChange change = scoreChanges.findById(scoreChangeId)
                .orElseThrow(RelationshipNotFoundException::new);
        relationship.scoreOf(change);
        return change;
    }

    private void attachScoreMedia(long actorId, long scoreChangeId, List<UUID> uploadIds) {
        RelationshipMediaFailures.translating(() -> mediaMutation.attachScoreChange(
                new AttachScoreChangeMediaCommand(actorId, scoreChangeId, uploadIds)));
    }

    private void attachCommentMedia(long actorId, long commentId, List<UUID> uploadIds) {
        RelationshipMediaFailures.translating(() -> mediaMutation.attachScoreComment(
                new AttachScoreCommentMediaCommand(actorId, commentId, uploadIds)));
    }

    private Map<Long, List<AttachedMedia>> scoreMedia(List<ScoreChange> changes) {
        if (changes.isEmpty()) {
            return Map.of();
        }
        try {
            return mediaQuery.attachmentsForScoreChanges(changes.stream()
                    .map(change -> new ScoreChangeMediaParent(
                            change.getId(), change.getChangedById()))
                    .toList());
        } catch (InvalidAttachedMediaQueryException | AttachedMediaUnavailableException exception) {
            throw new RelationshipUnavailableException(exception);
        }
    }

    private Map<Long, List<AttachedMedia>> commentMedia(List<ScoreChangeComment> thread) {
        if (thread.isEmpty()) {
            return Map.of();
        }
        try {
            return mediaQuery.attachmentsForScoreComments(thread.stream()
                    .map(comment -> new ScoreCommentMediaParent(
                            comment.getId(), comment.getAuthorId()))
                    .toList());
        } catch (InvalidAttachedMediaQueryException | AttachedMediaUnavailableException exception) {
            throw new RelationshipUnavailableException(exception);
        }
    }

    private Map<Long, Long> commentCounts(List<ScoreChange> changes) {
        if (changes.isEmpty()) {
            return Map.of();
        }
        return comments.countByScoreChangeIds(
                        changes.stream().map(ScoreChange::getId).toList())
                .stream()
                .collect(Collectors.toUnmodifiableMap(
                        ScoreChangeCommentRepository.CommentCount::getScoreChangeId,
                        ScoreChangeCommentRepository.CommentCount::getCommentCount));
    }

    private List<MediaView> media(
            Map<Long, List<AttachedMedia>> attachments,
            long parentId) {
        List<AttachedMedia> found = attachments.get(parentId);
        if (found == null) {
            throw new RelationshipUnavailableException();
        }
        return found.stream()
                .map(MediaView::from)
                .toList();
    }

    private ScoreChangeView scoreChange(
            ScoreChange change,
            long commentCount,
            List<MediaView> attachments,
            Relationship relationship) {
        RelationshipScore score = relationship.scoreOf(change);
        return new ScoreChangeView(
                change.getId(),
                participant(score.getSourceParticipantId(), relationship),
                participant(score.getTargetParticipantId(), relationship),
                participant(change.getChangedById(), relationship),
                change.getDelta(),
                change.getResultingScore(),
                change.getReason(),
                change.getCreatedAt(),
                commentCount,
                attachments);
    }

    private ScoreChangeCommentView scoreComment(
            ScoreChangeComment comment,
            List<MediaView> attachments,
            Relationship relationship) {
        String content = comment.getContent();
        if (content == null && attachments.isEmpty()) {
            throw new RelationshipUnavailableException();
        }
        return new ScoreChangeCommentView(
                comment.getId(),
                participant(comment.getAuthorId(), relationship),
                content,
                comment.getCreatedAt(),
                attachments);
    }

    private RelationshipScoreView score(
            RelationshipScore score,
            Relationship relationship) {
        return new RelationshipScoreView(
                participant(score.getSourceParticipantId(), relationship),
                participant(score.getTargetParticipantId(), relationship),
                score.getCurrentScore(),
                score.getUpdatedAt());
    }

    private ParticipantView participant(
            ParticipantReference participant,
            Relationship relationship) {
        return participant(participant.id(), relationship);
    }

    private ParticipantView participant(long participantId, Relationship relationship) {
        ParticipantReference reference = relationship.participantById(participantId);
        return ParticipantView.from(reference, relationship.isSelf(reference.id()));
    }
}
