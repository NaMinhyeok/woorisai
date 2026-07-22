package com.woorisai.media.internal;

import com.woorisai.media.AttachedMedia;
import com.woorisai.media.AttachedMediaQuery;
import com.woorisai.media.AttachedMediaQuery.AttachedMediaUnavailableException;
import com.woorisai.media.AttachedMediaQuery.InvalidAttachedMediaQueryException;
import com.woorisai.media.DiaryEntryMediaParent;
import com.woorisai.media.MediaKind;
import com.woorisai.media.ScoreChangeMediaParent;
import com.woorisai.media.ScoreCommentMediaParent;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.function.Function;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
class AttachedMediaQueryService implements AttachedMediaQuery {

    private static final Set<String> IMAGE_CONTENT_TYPES =
            Set.of("image/jpeg", "image/png", "image/webp");
    private static final Set<String> VIDEO_CONTENT_TYPES =
            Set.of("video/mp4", "video/webm", "video/quicktime");

    private final MediaAttachmentRepository attachments;

    @Override
    @Transactional(readOnly = true)
    public Map<Long, List<AttachedMedia>> attachmentsForScoreChanges(
            List<ScoreChangeMediaParent> parents) {
        Map<Long, Long> expected = validParents(
                parents,
                ScoreChangeMediaParent::scoreChangeId,
                ScoreChangeMediaParent::expectedUploaderId);
        try {
            List<MediaAttachment> found = expected.isEmpty()
                    ? List.of()
                    : attachments
                            .findAllByPurposeAndStatusAndScoreChangeIdInOrderByScoreChangeIdAscPositionAscIdAsc(
                                    MediaPurpose.SCORE_CHANGE,
                                    MediaStatus.READY,
                                    expected.keySet());
            return queryGroups(
                    expected,
                    found,
                    MediaAttachment::getScoreChangeId,
                    MediaAttachmentGroupPolicy.Group.SCORE);
        } catch (InvalidAttachedMediaQueryException | AttachedMediaUnavailableException exception) {
            throw exception;
        } catch (DataAccessException exception) {
            throw new AttachedMediaUnavailableException(exception);
        }
    }

    @Override
    @Transactional(readOnly = true)
    public Map<Long, List<AttachedMedia>> attachmentsForScoreComments(
            List<ScoreCommentMediaParent> parents) {
        if (parents == null || parents.stream().anyMatch(Objects::isNull)) {
            throw new InvalidAttachedMediaQueryException();
        }
        Map<Long, Long> expectedUploaders = new LinkedHashMap<>();
        for (ScoreCommentMediaParent parent : parents) {
            if (parent.scoreCommentId() <= 0
                    || parent.expectedUploaderId() <= 0
                    || expectedUploaders.putIfAbsent(
                                    parent.scoreCommentId(), parent.expectedUploaderId())
                            != null) {
                throw new InvalidAttachedMediaQueryException();
            }
        }
        try {
            List<MediaAttachment> found = expectedUploaders.isEmpty()
                    ? List.of()
                    : attachments
                            .findAllByPurposeAndStatusAndScoreChangeCommentIdInOrderByScoreChangeCommentIdAscPositionAscIdAsc(
                                    MediaPurpose.SCORE_CHANGE_COMMENT,
                                    MediaStatus.READY,
                                    expectedUploaders.keySet());
            return queryGroups(
                    expectedUploaders,
                    found,
                    MediaAttachment::getScoreChangeCommentId,
                    MediaAttachmentGroupPolicy.Group.FLEXIBLE);
        } catch (InvalidAttachedMediaQueryException | AttachedMediaUnavailableException exception) {
            throw exception;
        } catch (DataAccessException exception) {
            throw new AttachedMediaUnavailableException(exception);
        }
    }

    @Override
    @Transactional(readOnly = true)
    public Map<Long, List<AttachedMedia>> attachmentsForDiaryEntries(
            List<DiaryEntryMediaParent> parents) {
        Map<Long, Long> expected = validParents(
                parents,
                DiaryEntryMediaParent::diaryEntryId,
                DiaryEntryMediaParent::expectedUploaderId);
        try {
            List<MediaAttachment> found = expected.isEmpty()
                    ? List.of()
                    : attachments
                            .findAllByPurposeAndStatusAndDiaryEntryIdInOrderByDiaryEntryIdAscPositionAscIdAsc(
                                    MediaPurpose.DIARY_ENTRY,
                                    MediaStatus.READY,
                                    expected.keySet());
            return queryGroups(
                    expected,
                    found,
                    MediaAttachment::getDiaryEntryId,
                    MediaAttachmentGroupPolicy.Group.FLEXIBLE);
        } catch (InvalidAttachedMediaQueryException | AttachedMediaUnavailableException exception) {
            throw exception;
        } catch (DataAccessException exception) {
            throw new AttachedMediaUnavailableException(exception);
        }
    }

    private Map<Long, List<AttachedMedia>> queryGroups(
            Map<Long, Long> expectedUploaders,
            List<MediaAttachment> found,
            Function<MediaAttachment, Long> parentId,
            MediaAttachmentGroupPolicy.Group groupPolicy) {
        Map<Long, List<MediaAttachment>> groups = new LinkedHashMap<>();
        expectedUploaders.keySet().forEach(id -> groups.put(id, new ArrayList<>()));
        for (MediaAttachment attachment : found) {
            Long id = parentId.apply(attachment);
            List<MediaAttachment> group = groups.get(id);
            if (group == null
                    || attachment.getUploaderId() == null
                    || attachment.getUploaderId() <= 0
                    || attachment.getUploaderId().longValue() != expectedUploaders.get(id)
                    || !attachment.isParentedReady()) {
                throw unavailableQuery();
            }
            group.add(attachment);
        }

        Map<Long, List<AttachedMedia>> result = new LinkedHashMap<>();
        groups.forEach((id, media) -> {
            validateGroup(media, groupPolicy);
            result.put(id, media.stream().map(this::toAttached).toList());
        });
        return Collections.unmodifiableMap(result);
    }

    private static <T> Map<Long, Long> validParents(
            List<T> parents,
            Function<T, Long> id,
            Function<T, Long> uploader) {
        if (parents == null || parents.stream().anyMatch(Objects::isNull)) {
            throw new InvalidAttachedMediaQueryException();
        }
        Map<Long, Long> result = new LinkedHashMap<>();
        for (T parent : parents) {
            long parentId = id.apply(parent);
            long uploaderId = uploader.apply(parent);
            if (parentId <= 0
                    || uploaderId <= 0
                    || result.putIfAbsent(parentId, uploaderId) != null) {
                throw new InvalidAttachedMediaQueryException();
            }
        }
        return Collections.unmodifiableMap(result);
    }

    private static void validateGroup(
            List<MediaAttachment> group,
            MediaAttachmentGroupPolicy.Group policy) {
        if (!MediaAttachmentGroupPolicy.accepts(
                policy, group.stream().map(MediaAttachment::getKind).toList())) {
            throw unavailableQuery();
        }
        for (int position = 0; position < group.size(); position++) {
            MediaAttachment media = group.get(position);
            if (media.getPosition() == null || media.getPosition() != position) {
                throw unavailableQuery();
            }
        }
    }

    private AttachedMedia toAttached(MediaAttachment media) {
        Set<String> contentTypes = media.getKind() == MediaKind.IMAGE
                ? IMAGE_CONTENT_TYPES
                : VIDEO_CONTENT_TYPES;
        if (media.getActualSize() == null
                || media.getActualSize() <= 0
                || !Objects.equals(media.getExpectedSize(), media.getActualSize())
                || media.getOriginalName() == null
                || media.getOriginalName().isBlank()
                || media.getContentType() == null
                || !contentTypes.contains(media.getContentType())) {
            throw unavailableQuery();
        }
        return new AttachedMedia(
                media.getId(),
                media.getKind(),
                media.getOriginalName(),
                media.getContentType(),
                media.getActualSize());
    }

    private static AttachedMediaUnavailableException unavailableQuery() {
        return new AttachedMediaUnavailableException(
                new IllegalStateException("Stored media attachment is inconsistent"));
    }
}
