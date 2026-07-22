package com.woorisai.diary.internal;

import com.woorisai.diary.DiaryEntryCommentCreated;
import com.woorisai.media.AttachedMedia;
import com.woorisai.media.AttachedMediaQuery;
import com.woorisai.media.AttachedMediaQuery.AttachedMediaUnavailableException;
import com.woorisai.media.AttachedMediaQuery.InvalidAttachedMediaQueryException;
import com.woorisai.media.DiaryEntryMediaParent;
import com.woorisai.media.MediaAttachmentMutation;
import com.woorisai.media.MediaAttachmentMutation.InvalidMediaAttachmentRequestException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentConflictException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentForbiddenException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentUnavailableException;
import com.woorisai.media.MediaAttachmentMutation.MediaUploadNotFoundException;
import com.woorisai.media.ReplaceDiaryEntryMediaCommand;
import com.woorisai.participant.CanonicalParticipantPair;
import com.woorisai.participant.ParticipantDirectory;
import com.woorisai.participant.ParticipantDirectory.ParticipantPairUnavailableException;
import com.woorisai.participant.ParticipantReference;
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
import org.springframework.dao.DataIntegrityViolationException;
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
    DiaryEntryListResponse listEntries(long actorId, int pageNumber) {
        DiaryContext context = context(actorId);
        Page<DiaryEntry> page = entries.findAllByOrderByCreatedAtDescIdDesc(
                PageRequest.of(pageNumber - 1, PAGE_SIZE));
        List<DiaryEntry> content = page.getContent();
        Map<Long, Long> commentCounts = commentCounts(content);
        Map<Long, List<DiaryMediaResponse>> media = attachments(content);
        List<DiaryEntryListItemResponse> results = content.stream()
                .map(entry -> listItem(
                        entry,
                        context,
                        media.get(entry.getId()),
                        commentCounts.getOrDefault(entry.getId(), 0L)))
                .toList();
        return new DiaryEntryListResponse(
                results,
                pageNumber,
                PAGE_SIZE,
                page.hasNext(),
                page.getTotalElements());
    }

    @Transactional(readOnly = true)
    DiaryEntryDetailResponse getEntry(long actorId, long entryId) {
        DiaryContext context = context(actorId);
        DiaryEntry entry = entries.findById(entryId)
                .orElseThrow(DiaryEntryNotFoundException::new);
        ParticipantReference author = canonicalAuthor(entry.getAuthorId(), context);
        List<DiaryEntryComment> thread = comments
                .findAllByDiaryEntryIdOrderByCreatedAtAscIdAsc(entryId);
        List<DiaryCommentResponse> commentResponses = thread.stream()
                .map(comment -> commentResponse(comment, context))
                .toList();
        List<DiaryMediaResponse> media = attachments(List.of(entry)).get(entryId);
        return new DiaryEntryDetailResponse(
                entry.getId(),
                DiaryParticipantResponse.from(author),
                entry.getContent(),
                entry.getCreatedAt(),
                entry.getUpdatedAt(),
                entry.getAuthorId() == context.actor().id(),
                media,
                commentResponses.size(),
                commentResponses);
    }

    @Transactional
    DiaryEntryCreatedResponse createEntry(
            long actorId,
            CreateDiaryEntryCommand command) {
        DiaryContext context = context(actorId);
        DiaryEntry entry = entries.saveAndFlush(DiaryEntry.create(
                context.actor().id(), command.content(), now()));
        replaceDiaryMedia(
                context.actor().id(), entry.getId(), command.mediaUploadIds().values());
        List<DiaryMediaResponse> media = attachments(List.of(entry)).get(entry.getId());
        return new DiaryEntryCreatedResponse(
                entry.getId(),
                DiaryParticipantResponse.from(context.actor()),
                entry.getContent(),
                entry.getCreatedAt(),
                entry.getUpdatedAt(),
                true,
                media,
                0);
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
        return new DiaryEntryUpdatedResponse(
                entry.getId(),
                DiaryParticipantResponse.from(context.actor()),
                entry.getContent(),
                entry.getCreatedAt(),
                entry.getUpdatedAt(),
                true,
                media,
                commentCount);
    }

    @Transactional
    void deleteEntry(long actorId, long entryId) {
        DiaryContext context = context(actorId);
        DiaryEntry entry = entry(entryId, context);
        entry.requireDeletionBy(context.actor().id());
        entries.delete(entry);
        flushEntries();
    }

    @Transactional
    DiaryEntryCommentCreatedResponse createComment(
            long actorId,
            long entryId,
            CreateDiaryCommentCommand command) {
        DiaryContext context = context(actorId);
        entry(entryId, context);
        DiaryEntryComment comment;
        try {
            comment = comments.saveAndFlush(DiaryEntryComment.create(
                    entryId,
                    context.actor().id(),
                    command.content(),
                    now()));
        } catch (DataIntegrityViolationException exception) {
            if (DiaryConstraintViolationClassifier.isDeletedEntryConflict(exception)) {
                throw new DiaryConflictException(exception);
            }
            throw exception;
        }
        events.publishEvent(new DiaryEntryCommentCreated(
                context.recipient().id(), entryId));
        return createdCommentResponse(comment, context.actor());
    }

    @Transactional
    DiaryEntryCommentUpdatedResponse updateComment(
            long actorId,
            long commentId,
            UpdateDiaryCommentCommand command) {
        DiaryContext context = context(actorId);
        DiaryEntryComment comment = commentWithParent(commentId, context);
        comment.reviseBy(context.actor().id(), command.content(), now());
        flushComments();
        return updatedCommentResponse(comment, context.actor());
    }

    @Transactional
    void deleteComment(long actorId, long commentId) {
        DiaryContext context = context(actorId);
        DiaryEntryComment comment = commentWithParent(commentId, context);
        comment.requireDeletionBy(context.actor().id());
        comments.delete(comment);
        flushComments();
    }

    private DiaryEntryComment commentWithParent(long commentId, DiaryContext context) {
        DiaryEntryComment comment = comments.findById(commentId)
                .orElseThrow(DiaryCommentNotFoundException::new);
        entry(comment.getDiaryEntryId(), context);
        canonicalAuthor(comment.getAuthorId(), context);
        return comment;
    }

    private DiaryEntry entry(long entryId, DiaryContext context) {
        DiaryEntry entry = entries.findById(entryId)
                .orElseThrow(DiaryEntryNotFoundException::new);
        canonicalAuthor(entry.getAuthorId(), context);
        return entry;
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
        try {
            mediaMutation.replaceDiaryEntry(
                    new ReplaceDiaryEntryMediaCommand(actorId, entryId, uploadIds));
        } catch (InvalidMediaAttachmentRequestException
                | MediaUploadNotFoundException
                | MediaAttachmentForbiddenException
                | MediaAttachmentConflictException exception) {
            throw new InvalidDiaryRequestException();
        } catch (MediaAttachmentUnavailableException exception) {
            throw new DiaryUnavailableException(exception);
        }
    }

    private DiaryEntryListItemResponse listItem(
            DiaryEntry entry,
            DiaryContext context,
            List<DiaryMediaResponse> media,
            long commentCount) {
        ParticipantReference author = canonicalAuthor(entry.getAuthorId(), context);
        return new DiaryEntryListItemResponse(
                entry.getId(),
                DiaryParticipantResponse.from(author),
                entry.getContent(),
                entry.getCreatedAt(),
                entry.getUpdatedAt(),
                author.id() == context.actor().id(),
                media,
                commentCount);
    }

    private DiaryCommentResponse commentResponse(
            DiaryEntryComment comment,
            DiaryContext context) {
        ParticipantReference author = canonicalAuthor(comment.getAuthorId(), context);
        return new DiaryCommentResponse(
                comment.getId(),
                DiaryParticipantResponse.from(author),
                comment.getContent(),
                comment.getCreatedAt(),
                comment.getUpdatedAt(),
                author.id() == context.actor().id());
    }

    private static DiaryEntryCommentCreatedResponse createdCommentResponse(
            DiaryEntryComment comment,
            ParticipantReference author) {
        return new DiaryEntryCommentCreatedResponse(
                comment.getId(),
                DiaryParticipantResponse.from(author),
                comment.getContent(),
                comment.getCreatedAt(),
                comment.getUpdatedAt(),
                true);
    }

    private static DiaryEntryCommentUpdatedResponse updatedCommentResponse(
            DiaryEntryComment comment,
            ParticipantReference author) {
        return new DiaryEntryCommentUpdatedResponse(
                comment.getId(),
                DiaryParticipantResponse.from(author),
                comment.getContent(),
                comment.getCreatedAt(),
                comment.getUpdatedAt(),
                true);
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

    private static ParticipantReference canonicalAuthor(
            long authorId,
            DiaryContext context) {
        return context.participants()
                .findById(authorId)
                .orElseThrow(DiaryUnavailableException::new);
    }

    private Instant now() {
        return Instant.now(clock).truncatedTo(ChronoUnit.MICROS);
    }

    private record DiaryContext(
            ParticipantReference actor,
            ParticipantReference recipient,
            CanonicalParticipantPair participants) {}

}
