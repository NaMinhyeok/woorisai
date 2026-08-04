package com.woorisai.diary.internal;

import com.woorisai.diary.DiaryEntryCommentCreated;
import com.woorisai.media.AttachedMedia;
import com.woorisai.media.AttachedMediaQuery;
import com.woorisai.media.AttachedMediaQuery.AttachedMediaUnavailableException;
import com.woorisai.media.AttachedMediaQuery.InvalidAttachedMediaQueryException;
import com.woorisai.media.DiaryEntryMediaParent;
import com.woorisai.media.MediaAttachmentMutation;
import com.woorisai.media.ReplaceDiaryEntryMediaCommand;
import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantDirectory.ParticipantPairUnavailableException;
import com.woorisai.participant.ParticipantReference;
import com.woorisai.support.paging.PageResponse;
import java.time.Clock;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashMap;
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
class DiaryService {

    private static final int PAGE_SIZE = 20;

    private final DiaryEntryRepository entries;
    private final DiaryEntryCommentRepository comments;
    private final ParticipantDirectory participants;
    private final MediaAttachmentMutation mediaMutation;
    private final AttachedMediaQuery attachedMedia;
    private final ApplicationEventPublisher events;
    private final Clock clock;

    @Transactional(readOnly = true)
    PageResponse<DiaryEntryResponse> listEntries(long actorId, int pageNumber) {
        DiaryContext context = context(actorId);
        Page<DiaryEntry> page = entries.findAllByDeletedAtIsNullOrderByCreatedAtDescIdDesc(
                PageRequest.of(pageNumber - 1, PAGE_SIZE));
        List<DiaryEntry> content = page.getContent();
        Map<Long, Long> commentCounts = commentCounts(content);
        Map<Long, List<DiaryMediaResponse>> media = attachments(content);
        return PageResponse.of(page, entry -> DiaryEntryResponse.of(
                entry,
                context.authorshipOf(entry.getAuthorId()),
                media.get(entry.getId()),
                commentCounts.getOrDefault(entry.getId(), 0L)));
    }

    @Transactional(readOnly = true)
    DiaryEntryDetailResponse getEntry(long actorId, long entryId) {
        DiaryContext context = context(actorId);
        DiaryEntry entry = liveEntry(entryId);
        List<DiaryEntryComment> thread = liveComments(entryId).stream()
                .sorted(DiaryEntryComment.IN_THREAD_ORDER)
                .toList();
        List<DiaryCommentResponse> commentResponses = thread.stream()
                .map(comment -> DiaryCommentResponse.of(
                        comment, context.authorshipOf(comment.getAuthorId())))
                .toList();
        List<DiaryMediaResponse> media = attachments(List.of(entry)).get(entryId);
        return DiaryEntryDetailResponse.of(
                entry,
                context.authorshipOf(entry.getAuthorId()),
                media,
                commentResponses);
    }

    @Transactional
    DiaryEntryResponse createEntry(
            long actorId,
            CreateDiaryEntryCommand command) {
        DiaryContext context = context(actorId);
        DiaryEntry entry = entries.saveAndFlush(DiaryEntry.create(
                context.actor().id(), command.content(), now()));
        replaceDiaryMedia(
                context.actor().id(), entry.getId(), command.mediaUploadIds().values());
        List<DiaryMediaResponse> media = attachments(List.of(entry)).get(entry.getId());
        return DiaryEntryResponse.of(
                entry, context.authorshipOf(entry.getAuthorId()), media, 0);
    }

    @Transactional
    DiaryEntryUpdatedResponse updateEntry(
            long actorId,
            long entryId,
            UpdateDiaryEntryCommand command) {
        DiaryContext context = context(actorId);
        DiaryEntry entry = entry(entryId, context);
        entry.reviseBy(context.actor().id(), command.content(), now());
        flushEntries();
        command.mediaUploadIds().ifPresent(mediaUploadIds -> replaceDiaryMedia(
                context.actor().id(), entry.getId(), mediaUploadIds.values()));
        List<DiaryMediaResponse> media = attachments(List.of(entry)).get(entryId);
        long commentCount = comments.countByDiaryEntryIds(List.of(entryId)).stream()
                .mapToLong(DiaryEntryCommentCount::getCommentCount)
                .findFirst()
                .orElse(0);
        return DiaryEntryUpdatedResponse.of(
                entry, context.authorshipOf(entry.getAuthorId()), media, commentCount);
    }

    @Transactional
    void deleteEntry(long actorId, long entryId) {
        DiaryContext context = context(actorId);
        DiaryEntry entry = entry(entryId, context);
        Instant deletedAt = now();
        entry.deleteBy(context.actor().id(), deletedAt);
        // The parent no longer disappears physically, so ON DELETE CASCADE cannot
        // clear the thread. Mark the live children in the same transaction.
        liveComments(entryId).forEach(comment -> comment.deleteWithParent(deletedAt));
        flushComments();
        flushEntries();
    }

    @Transactional
    DiaryCommentResponse createComment(
            long actorId,
            long entryId,
            CreateDiaryCommentCommand command) {
        DiaryContext context = context(actorId);
        // 404 for an entry that never existed, plus the participant check.
        entry(entryId, context);
        // Then close the race: if the partner's delete commits between the two,
        // the locked read comes back empty and this stays a 409 like the dropped
        // foreign key produced.
        lockLiveEntry(entryId);
        DiaryEntryComment comment = comments.saveAndFlush(DiaryEntryComment.create(
                entryId,
                context.actor().id(),
                command.content(),
                now()));
        events.publishEvent(new DiaryEntryCommentCreated(
                context.recipient().id(), entryId));
        return DiaryCommentResponse.of(
                comment, context.authorshipOf(comment.getAuthorId()));
    }

    @Transactional
    DiaryCommentUpdatedResponse updateComment(
            long actorId,
            long commentId,
            UpdateDiaryCommentCommand command) {
        DiaryContext context = context(actorId);
        DiaryEntryComment comment = commentWithParent(commentId, context);
        comment.reviseBy(context.actor().id(), command.content(), now());
        flushComments();
        return DiaryCommentUpdatedResponse.of(
                comment, context.authorshipOf(comment.getAuthorId()));
    }

    @Transactional
    void deleteComment(long actorId, long commentId) {
        DiaryContext context = context(actorId);
        DiaryEntryComment comment = commentWithParent(commentId, context);
        comment.deleteBy(context.actor().id(), now());
        flushComments();
    }

    private DiaryEntryComment commentWithParent(long commentId, DiaryContext context) {
        DiaryEntryComment comment = comments.findById(commentId)
                .filter(DiaryEntryComment::isActive)
                .orElseThrow(DiaryCommentNotFoundException::new);
        entry(comment.getDiaryEntryId(), context);
        context.canonicalAuthor(comment.getAuthorId());
        return comment;
    }

    private DiaryEntry entry(long entryId, DiaryContext context) {
        DiaryEntry entry = liveEntry(entryId);
        context.canonicalAuthor(entry.getAuthorId());
        return entry;
    }

    private DiaryEntry liveEntry(long entryId) {
        return entries.findById(entryId)
                .filter(DiaryEntry::isActive)
                .orElseThrow(DiaryEntryNotFoundException::new);
    }

    private List<DiaryEntryComment> liveComments(long entryId) {
        return comments.findAllByDiaryEntryId(entryId).stream()
                .filter(DiaryEntryComment::isActive)
                .toList();
    }

    private void lockLiveEntry(long entryId) {
        if (entries.lockLiveEntryForCommentCreation(entryId).isEmpty()) {
            throw new DiaryConflictException();
        }
    }

    private void flushEntries() {
        try {
            entries.flush();
        } catch (OptimisticLockingFailureException exception) {
            throw new DiaryConflictException(exception);
        }
    }

    private void flushComments() {
        try {
            comments.flush();
        } catch (OptimisticLockingFailureException exception) {
            throw new DiaryConflictException(exception);
        }
    }

    private Map<Long, Long> commentCounts(List<DiaryEntry> entries) {
        if (entries.isEmpty()) {
            return Map.of();
        }
        List<Long> entryIds = entries.stream().map(DiaryEntry::getId).toList();
        return comments.countByDiaryEntryIds(entryIds).stream()
                .collect(Collectors.toUnmodifiableMap(
                        DiaryEntryCommentCount::getDiaryEntryId,
                        DiaryEntryCommentCount::getCommentCount));
    }

    private Map<Long, List<DiaryMediaResponse>> attachments(List<DiaryEntry> entries) {
        if (entries.isEmpty()) {
            return Map.of();
        }
        List<DiaryEntryMediaParent> parents = entries.stream()
                .map(entry -> new DiaryEntryMediaParent(entry.getId(), entry.getAuthorId()))
                .toList();
        Map<Long, List<AttachedMedia>> found;
        try {
            found = attachedMedia.attachmentsForDiaryEntries(parents);
        } catch (InvalidAttachedMediaQueryException | AttachedMediaUnavailableException exception) {
            throw new DiaryUnavailableException(exception);
        }
        if (found == null || found.size() != entries.size()) {
            throw new DiaryUnavailableException();
        }
        Map<Long, List<DiaryMediaResponse>> result = new LinkedHashMap<>();
        for (DiaryEntry entry : entries) {
            List<AttachedMedia> media = found.get(entry.getId());
            if (media == null) {
                throw new DiaryUnavailableException();
            }
            result.put(entry.getId(), media.stream()
                    .map(DiaryMediaResponse::from)
                    .toList());
        }
        return Map.copyOf(result);
    }

    private void replaceDiaryMedia(long actorId, long entryId, List<UUID> uploadIds) {
        DiaryMediaFailures.translating(() -> mediaMutation.replaceDiaryEntry(
                new ReplaceDiaryEntryMediaCommand(actorId, entryId, uploadIds)));
    }

    private DiaryContext context(long actorId) {
        CanonicalParticipantPair pair;
        try {
            pair = participants.canonicalPair();
        } catch (ParticipantPairUnavailableException exception) {
            throw new DiaryUnavailableException(exception);
        }
        ParticipantReference canonicalActor = pair.findById(actorId)
                .orElseThrow(DiaryMutationForbiddenException::new);
        ParticipantReference recipient = pair.partnerOf(canonicalActor.id())
                .orElseThrow(DiaryUnavailableException::new);
        return new DiaryContext(canonicalActor, recipient, pair);
    }

    private Instant now() {
        return Instant.now(clock).truncatedTo(ChronoUnit.MICROS);
    }

    private record DiaryContext(
            ParticipantReference actor,
            ParticipantReference recipient,
            CanonicalParticipantPair participants) {

        ParticipantReference canonicalAuthor(long authorId) {
            return participants.findById(authorId)
                    .orElseThrow(DiaryUnavailableException::new);
        }

        DiaryAuthorship authorshipOf(long authorId) {
            return DiaryAuthorship.of(canonicalAuthor(authorId), actor);
        }
    }

}
