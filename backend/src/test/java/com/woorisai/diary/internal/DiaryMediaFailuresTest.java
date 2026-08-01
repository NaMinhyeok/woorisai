package com.woorisai.diary.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.woorisai.media.MediaAttachmentMutation.InvalidMediaAttachmentRequestException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentConflictException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentForbiddenException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentUnavailableException;
import com.woorisai.media.MediaAttachmentMutation.MediaUploadNotFoundException;
import com.woorisai.support.error.ApplicationException;
import java.util.stream.Stream;
import org.junit.jupiter.api.Named;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

class DiaryMediaFailuresTest {

    static Stream<Arguments> translations() {
        return Stream.of(
                translation(
                        new InvalidMediaAttachmentRequestException(),
                        InvalidDiaryRequestException.class,
                        DiaryError.INVALID_REQUEST),
                translation(
                        new MediaUploadNotFoundException(),
                        DiaryMediaUploadNotFoundException.class,
                        DiaryError.NOT_FOUND),
                translation(
                        new MediaAttachmentForbiddenException(),
                        DiaryMediaForbiddenException.class,
                        DiaryError.FORBIDDEN),
                translation(
                        new MediaAttachmentConflictException(),
                        DiaryConflictException.class,
                        DiaryError.CONFLICT),
                translation(
                        new MediaAttachmentUnavailableException(),
                        DiaryUnavailableException.class,
                        DiaryError.UNAVAILABLE));
    }

    private static Arguments translation(
            RuntimeException mediaFailure,
            Class<? extends ApplicationException> expectedType,
            DiaryError expectedError) {
        return Arguments.of(named(mediaFailure), expectedType, expectedError);
    }

    @ParameterizedTest(name = "{0} is published as {2}")
    @MethodSource("translations")
    void translatesEachMediaAttachmentFailureToItsDiaryCode(
            RuntimeException mediaFailure,
            Class<? extends ApplicationException> expectedType,
            DiaryError expectedError) {
        assertThatThrownBy(() -> DiaryMediaFailures.translating(() -> {
            throw mediaFailure;
        }))
                .isInstanceOf(expectedType)
                .extracting(failure -> ((ApplicationException) failure).error())
                .isEqualTo(expectedError);
    }

    @Test
    void keepsTheMediaCauseOnAvailabilityFailures() {
        var unavailable = new MediaAttachmentUnavailableException();

        assertThatThrownBy(() -> DiaryMediaFailures.translating(() -> {
            throw unavailable;
        }))
                .hasCause(unavailable);
    }

    @ParameterizedTest(name = "{0} is reported without a cause")
    @MethodSource("callerMistakes")
    void dropsTheMediaCauseOnCallerMistakes(RuntimeException mediaFailure) {
        assertThatThrownBy(() -> DiaryMediaFailures.translating(() -> {
            throw mediaFailure;
        }))
                .hasNoCause();
    }

    static Stream<Arguments> callerMistakes() {
        return Stream.of(
                Arguments.of(named(new InvalidMediaAttachmentRequestException())),
                Arguments.of(named(new MediaUploadNotFoundException())),
                Arguments.of(named(new MediaAttachmentForbiddenException())),
                Arguments.of(named(new MediaAttachmentConflictException())));
    }

    private static Named<RuntimeException> named(RuntimeException mediaFailure) {
        return Named.of(mediaFailure.getClass().getSimpleName(), mediaFailure);
    }

    @Test
    void letsUnrelatedFailuresThroughInsteadOfReportingThemAsDiaryFailures() {
        var defect = new IllegalStateException("synthetic defect");

        assertThatThrownBy(() -> DiaryMediaFailures.translating(() -> {
            throw defect;
        }))
                .isSameAs(defect);
    }

    @Test
    void runsTheAttachmentWhenMediaAcceptsIt() {
        var attached = new boolean[1];

        DiaryMediaFailures.translating(() -> attached[0] = true);

        assertThat(attached[0]).isTrue();
    }
}
