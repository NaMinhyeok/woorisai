package com.woorisai.media.internal;

import com.woorisai.media.AttachScoreChangeMediaCommand;
import com.woorisai.media.AttachScoreCommentMediaCommand;
import com.woorisai.media.MediaAttachmentMutation;
import com.woorisai.media.MediaAttachmentMutation.InvalidMediaAttachmentRequestException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentConflictException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentForbiddenException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentUnavailableException;
import com.woorisai.media.MediaAttachmentMutation.MediaUploadNotFoundException;
import com.woorisai.media.ReplaceDiaryEntryMediaCommand;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
class MediaAttachmentMutationService implements MediaAttachmentMutation {

    private final MediaAttachmentRepository attachments;

    @Override
    @Transactional(propagation = Propagation.MANDATORY)
    public void attachScoreChange(AttachScoreChangeMediaCommand command) {
        if (command == null
                || command.expectedUploaderId() <= 0
                || command.scoreChangeId() <= 0) {
            throw new InvalidMediaAttachmentRequestException();
        }
        List<UUID> requested = validIds(
                command.mediaUploadIds(),
                MediaAttachmentGroupPolicy.Group.SCORE.maximum());
        List<MediaAttachment> locked = lockRequested(requested);
        if (!locked.isEmpty()) {
            MediaAttachment attachment = inRequestOrder(requested, locked).getFirst();
            requireAttachable(
                    attachment,
                    command.expectedUploaderId(),
                    MediaPurpose.SCORE_CHANGE);
            requireGroup(List.of(attachment), MediaAttachmentGroupPolicy.Group.SCORE);
            try {
                attachment.attachScoreChange(command.scoreChangeId());
                attachments.flush();
            } catch (IllegalStateException exception) {
                throw new MediaAttachmentConflictException();
            } catch (DataAccessException exception) {
                throw new MediaAttachmentUnavailableException(exception);
            }
        }
    }

    @Override
    @Transactional(propagation = Propagation.MANDATORY)
    public void attachScoreComment(AttachScoreCommentMediaCommand command) {
        if (command == null
                || command.expectedUploaderId() <= 0
                || command.scoreCommentId() <= 0) {
            throw new InvalidMediaAttachmentRequestException();
        }
        List<UUID> requested = validIds(
                command.mediaUploadIds(),
                MediaAttachmentGroupPolicy.Group.FLEXIBLE.maximum());
        List<MediaAttachment> ordered = inRequestOrder(requested, lockRequested(requested));
        ordered.forEach(attachment -> requireAttachable(
                attachment,
                command.expectedUploaderId(),
                MediaPurpose.SCORE_CHANGE_COMMENT));
        requireGroup(ordered, MediaAttachmentGroupPolicy.Group.FLEXIBLE);
        try {
            for (int position = 0; position < ordered.size(); position++) {
                ordered.get(position).attachScoreComment(command.scoreCommentId(), (short) position);
            }
            attachments.flush();
        } catch (IllegalStateException exception) {
            throw new MediaAttachmentConflictException();
        } catch (DataAccessException exception) {
            throw new MediaAttachmentUnavailableException(exception);
        }
    }

    @Override
    @Transactional(propagation = Propagation.MANDATORY)
    public void replaceDiaryEntry(ReplaceDiaryEntryMediaCommand command) {
        if (command == null
                || command.expectedUploaderId() <= 0
                || command.diaryEntryId() <= 0) {
            throw new InvalidMediaAttachmentRequestException();
        }
        List<UUID> requested = validIds(
                command.mediaUploadIds(),
                MediaAttachmentGroupPolicy.Group.FLEXIBLE.maximum());
        try {
            List<UUID> currentIds = attachments.findIdsByDiaryEntryId(command.diaryEntryId());
            Set<UUID> allIds = new LinkedHashSet<>(currentIds);
            allIds.addAll(requested);
            List<MediaAttachment> locked = allIds.isEmpty()
                    ? List.of()
                    : attachments.findAllByIdForUpdate(allIds);
            if (locked.size() != allIds.size()) {
                throw new MediaUploadNotFoundException();
            }
            Map<UUID, MediaAttachment> byId = byId(locked);
            List<MediaAttachment> ordered = requested.stream().map(byId::get).toList();
            for (MediaAttachment attachment : ordered) {
                requireDiaryReplaceable(
                        attachment,
                        command.expectedUploaderId(),
                        command.diaryEntryId());
            }
            requireGroup(ordered, MediaAttachmentGroupPolicy.Group.FLEXIBLE);

            List<MediaAttachment> current = currentIds.stream().map(byId::get).toList();
            for (MediaAttachment attachment : current) {
                if (attachment == null
                        || attachment.getUploaderId() != command.expectedUploaderId()
                        || attachment.getPurpose() != MediaPurpose.DIARY_ENTRY
                        || !attachment.isAttachedToDiary(command.diaryEntryId())) {
                    throw new MediaAttachmentUnavailableException();
                }
                attachment.detach();
            }
            attachments.flush();

            Set<UUID> retained = new HashSet<>(requested);
            List<MediaAttachment> omitted = current.stream()
                    .filter(attachment -> !retained.contains(attachment.getId()))
                    .toList();
            if (!omitted.isEmpty()) {
                attachments.deleteAll(omitted);
                attachments.flush();
            }

            for (int position = 0; position < ordered.size(); position++) {
                ordered.get(position).attachDiaryEntry(command.diaryEntryId(), (short) position);
            }
            attachments.flush();
        } catch (InvalidMediaAttachmentRequestException
                | MediaUploadNotFoundException
                | MediaAttachmentForbiddenException
                | MediaAttachmentConflictException
                | MediaAttachmentUnavailableException exception) {
            throw exception;
        } catch (IllegalStateException exception) {
            throw new MediaAttachmentConflictException();
        } catch (DataAccessException exception) {
            throw new MediaAttachmentUnavailableException(exception);
        }
    }

    private List<MediaAttachment> lockRequested(List<UUID> requested) {
        if (requested.isEmpty()) {
            return List.of();
        }
        try {
            List<MediaAttachment> locked = attachments.findAllByIdForUpdate(requested);
            if (locked.size() != requested.size()) {
                throw new MediaUploadNotFoundException();
            }
            return locked;
        } catch (MediaUploadNotFoundException exception) {
            throw exception;
        } catch (DataAccessException exception) {
            throw new MediaAttachmentUnavailableException(exception);
        }
    }

    private static List<UUID> validIds(List<UUID> ids, int maximum) {
        if (ids == null
                || ids.size() > maximum
                || ids.stream().anyMatch(Objects::isNull)
                || new HashSet<>(ids).size() != ids.size()) {
            throw new InvalidMediaAttachmentRequestException();
        }
        return List.copyOf(ids);
    }

    private static List<MediaAttachment> inRequestOrder(
            List<UUID> requested,
            Collection<MediaAttachment> locked) {
        Map<UUID, MediaAttachment> byId = byId(locked);
        List<MediaAttachment> ordered = requested.stream().map(byId::get).toList();
        if (ordered.stream().anyMatch(Objects::isNull)) {
            throw new MediaUploadNotFoundException();
        }
        return ordered;
    }

    private static Map<UUID, MediaAttachment> byId(Collection<MediaAttachment> attachments) {
        Map<UUID, MediaAttachment> byId = new LinkedHashMap<>();
        attachments.forEach(attachment -> byId.put(attachment.getId(), attachment));
        return byId;
    }

    private static void requireAttachable(
            MediaAttachment attachment,
            long uploaderId,
            MediaPurpose purpose) {
        if (attachment.getUploaderId() != uploaderId) {
            throw new MediaAttachmentForbiddenException();
        }
        if (attachment.getPurpose() != purpose) {
            throw new InvalidMediaAttachmentRequestException();
        }
        if (attachment.getStatus() != MediaStatus.READY || !attachment.isParentless()) {
            throw new MediaAttachmentConflictException();
        }
    }

    private static void requireDiaryReplaceable(
            MediaAttachment attachment,
            long uploaderId,
            long diaryEntryId) {
        if (attachment.getUploaderId() != uploaderId) {
            throw new MediaAttachmentForbiddenException();
        }
        if (attachment.getPurpose() != MediaPurpose.DIARY_ENTRY) {
            throw new InvalidMediaAttachmentRequestException();
        }
        if (attachment.getStatus() != MediaStatus.READY
                || (!attachment.isParentless() && !attachment.isAttachedToDiary(diaryEntryId))) {
            throw new MediaAttachmentConflictException();
        }
    }

    private static void requireGroup(
            List<MediaAttachment> group,
            MediaAttachmentGroupPolicy.Group policy) {
        if (!MediaAttachmentGroupPolicy.accepts(
                policy, group.stream().map(MediaAttachment::getKind).toList())) {
            throw new InvalidMediaAttachmentRequestException();
        }
    }
}
