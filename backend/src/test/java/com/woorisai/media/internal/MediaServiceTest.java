package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;

import com.woorisai.media.MediaKind;
import java.net.URI;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.DataRetrievalFailureException;

class MediaServiceTest {

    private static final long ACTOR_ID = 3_000_000_001L;
    private static final UUID UPLOAD_ID =
            UUID.fromString("10000000-0000-4000-8000-000000000001");
    private static final Instant NOW = Instant.parse("2026-07-21T00:00:00Z");
    private static final byte[] PNG = new byte[] {
            (byte) 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a
    };

    private MediaAttachmentRepository attachments;
    private MediaObjectStorage objects;
    private MediaService service;

    @BeforeEach
    void setUp() {
        attachments = mock(MediaAttachmentRepository.class);
        objects = mock(MediaObjectStorage.class);
        service = new MediaService(
                attachments,
                objects,
                new MediaPolicy(900),
                300,
                Clock.fixed(NOW, ZoneOffset.UTC),
                () -> UPLOAD_ID);
    }

    @Test
    void mapsExpectedInitiationRepositoryAndStorageFailures() {
        var databaseFailure = new DataIntegrityViolationException("synthetic write failure");
        given(attachments.saveAndFlush(any(MediaAttachment.class)))
                .willThrow(databaseFailure);

        assertThatThrownBy(this::initiate)
                .isInstanceOf(MediaUploadInitiationUnavailableException.class)
                .hasCause(databaseFailure);

        attachments = mock(MediaAttachmentRepository.class);
        objects = mock(MediaObjectStorage.class);
        service = service(attachments, objects);
        var storageFailure = storageFailure();
        given(objects.presignUpload(any(UploadPresignRequest.class)))
                .willThrow(storageFailure);

        assertThatThrownBy(this::initiate)
                .isInstanceOf(MediaUploadInitiationUnavailableException.class)
                .hasCause(storageFailure);
    }

    @Test
    void mapsExpectedCompletionStorageFailuresAndMissingObjects() {
        MediaAttachment pending = pending();
        given(attachments.findByIdForUpdate(UPLOAD_ID)).willReturn(Optional.of(pending));
        var storageFailure = storageFailure();
        given(objects.inspect("pending/" + UPLOAD_ID)).willThrow(storageFailure);

        assertThatThrownBy(() -> service.complete(ACTOR_ID, UPLOAD_ID))
                .isInstanceOf(MediaUploadCompletionUnavailableException.class)
                .hasCause(storageFailure);

        attachments = mock(MediaAttachmentRepository.class);
        objects = mock(MediaObjectStorage.class);
        service = service(attachments, objects);
        given(attachments.findByIdForUpdate(UPLOAD_ID)).willReturn(Optional.of(pending()));
        given(objects.inspect("pending/" + UPLOAD_ID))
                .willThrow(new MediaObjectNotFoundException(
                        new IllegalStateException("synthetic missing object")));

        assertThatThrownBy(() -> service.complete(ACTOR_ID, UPLOAD_ID))
                .isInstanceOf(MediaUploadCompletionConflictException.class);
    }

    @Test
    void mapsExpectedDiscardAndDownloadFailures() {
        var databaseFailure = new DataRetrievalFailureException("synthetic read failure");
        given(attachments.findByIdForUpdate(UPLOAD_ID)).willThrow(databaseFailure);

        assertThatThrownBy(() -> service.discard(ACTOR_ID, UPLOAD_ID))
                .isInstanceOf(MediaUploadDiscardUnavailableException.class)
                .hasCause(databaseFailure);

        attachments = mock(MediaAttachmentRepository.class);
        objects = mock(MediaObjectStorage.class);
        service = service(attachments, objects);
        given(attachments.findById(UPLOAD_ID)).willReturn(Optional.of(parentedReady()));
        var storageFailure = storageFailure();
        given(objects.presignDownload(any(DownloadPresignRequest.class)))
                .willThrow(storageFailure);

        assertThatThrownBy(() -> service.download(ACTOR_ID, UPLOAD_ID))
                .isInstanceOf(MediaDownloadUnavailableException.class)
                .hasCause(storageFailure);
    }

    @Test
    void doesNotHideUnexpectedRuntimeDefectsAsAvailabilityFailures() {
        var repositoryDefect = new IllegalStateException("synthetic repository defect");
        given(attachments.saveAndFlush(any(MediaAttachment.class))).willThrow(repositoryDefect);

        assertThatThrownBy(this::initiate).isSameAs(repositoryDefect);

        attachments = mock(MediaAttachmentRepository.class);
        objects = mock(MediaObjectStorage.class);
        service = service(attachments, objects);
        var storageDefect = new IllegalStateException("synthetic storage adapter defect");
        given(objects.presignUpload(any(UploadPresignRequest.class)))
                .willThrow(storageDefect);

        assertThatThrownBy(this::initiate).isSameAs(storageDefect);
    }

    @Test
    void normalizesUppercaseHttpsUrls() {
        var normalized = new MediaDownloadGrant(
                URI.create("HTTPS://downloads.example.test/media/normalized"),
                NOW.plusSeconds(300));

        assertThat(normalized.downloadUrl().toString())
                .isEqualTo("https://downloads.example.test/media/normalized");
    }

    @Test
    void rejectsInvalidPrivateUrlsWithoutExposingThem() {
        URI invalid = URI.create("http://user:secret@example.test/media#credential");

        assertThatThrownBy(() -> new MediaDownloadGrant(invalid, NOW.plusSeconds(300)))
                .isInstanceOf(MediaDownloadUnavailableException.class)
                .hasCauseInstanceOf(IllegalStateException.class)
                .hasMessageNotContaining(invalid.toString())
                .hasRootCauseMessage("Presigned media URL is invalid");
    }

    private InitiatedMediaUpload initiate() {
        return service.initiate(
                ACTOR_ID,
                MediaPurpose.DIARY_ENTRY,
                MediaKind.IMAGE,
                "fixture.png",
                "image/png",
                PNG.length);
    }

    private static MediaService service(
            MediaAttachmentRepository attachments,
            MediaObjectStorage objects) {
        return new MediaService(
                attachments,
                objects,
                new MediaPolicy(900),
                300,
                Clock.fixed(NOW, ZoneOffset.UTC),
                () -> UPLOAD_ID);
    }

    private static MediaAttachment pending() {
        return MediaAttachment.pending(
                UPLOAD_ID,
                ACTOR_ID,
                MediaPurpose.DIARY_ENTRY,
                MediaKind.IMAGE,
                "pending/" + UPLOAD_ID,
                "fixture.png",
                "image/png",
                PNG.length,
                NOW);
    }

    private static MediaAttachment parentedReady() {
        MediaAttachment attachment = pending();
        attachment.complete("media/" + UPLOAD_ID, PNG.length, NOW.plusSeconds(1));
        attachment.attachDiaryEntry(40L, (short) 0);
        return attachment;
    }

    private static MediaObjectStorageException storageFailure() {
        return new MediaObjectStorageException(
                new IllegalStateException("synthetic storage failure"));
    }
}
