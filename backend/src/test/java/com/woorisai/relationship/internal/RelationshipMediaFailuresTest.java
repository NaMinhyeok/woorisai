package com.woorisai.relationship.internal;

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

class RelationshipMediaFailuresTest {

    static Stream<Arguments> translations() {
        return Stream.of(
                translation(
                        new InvalidMediaAttachmentRequestException(),
                        InvalidRelationshipRequestException.class,
                        RelationshipError.INVALID_REQUEST),
                translation(
                        new MediaUploadNotFoundException(),
                        RelationshipNotFoundException.class,
                        RelationshipError.NOT_FOUND),
                translation(
                        new MediaAttachmentForbiddenException(),
                        RelationshipForbiddenException.class,
                        RelationshipError.FORBIDDEN),
                translation(
                        new MediaAttachmentConflictException(),
                        RelationshipConflictException.class,
                        RelationshipError.CONFLICT),
                translation(
                        new MediaAttachmentUnavailableException(),
                        RelationshipUnavailableException.class,
                        RelationshipError.UNAVAILABLE));
    }

    private static Arguments translation(
            RuntimeException mediaFailure,
            Class<? extends ApplicationException> expectedType,
            RelationshipError expectedError) {
        return Arguments.of(named(mediaFailure), expectedType, expectedError);
    }

    @ParameterizedTest(name = "{0} is published as {2}")
    @MethodSource("translations")
    void translatesEachMediaAttachmentFailureToItsRelationshipCode(
            RuntimeException mediaFailure,
            Class<? extends ApplicationException> expectedType,
            RelationshipError expectedError) {
        assertThatThrownBy(() -> RelationshipMediaFailures.translating(() -> {
            throw mediaFailure;
        }))
                .isInstanceOf(expectedType)
                .extracting(failure -> ((ApplicationException) failure).error())
                .isEqualTo(expectedError);
    }

    @Test
    void keepsTheMediaCauseOnAvailabilityFailures() {
        var unavailable = new MediaAttachmentUnavailableException();

        assertThatThrownBy(() -> RelationshipMediaFailures.translating(() -> {
            throw unavailable;
        }))
                .hasCause(unavailable);
    }

    @ParameterizedTest(name = "{0} is reported without a cause")
    @MethodSource("callerMistakes")
    void dropsTheMediaCauseOnCallerMistakes(RuntimeException mediaFailure) {
        assertThatThrownBy(() -> RelationshipMediaFailures.translating(() -> {
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
    void letsUnrelatedFailuresThroughInsteadOfReportingThemAsRelationshipFailures() {
        var defect = new IllegalStateException("synthetic defect");

        assertThatThrownBy(() -> RelationshipMediaFailures.translating(() -> {
            throw defect;
        }))
                .isSameAs(defect);
    }

    @Test
    void runsTheAttachmentWhenMediaAcceptsIt() {
        var attached = new boolean[1];

        RelationshipMediaFailures.translating(() -> attached[0] = true);

        assertThat(attached[0]).isTrue();
    }
}
