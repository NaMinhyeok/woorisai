package com.woorisai.support.error;

import static org.assertj.core.api.Assertions.assertThat;

import com.woorisai.support.error.PublishedProblemContract.PublishedProblem;
import java.lang.reflect.InvocationTargetException;
import java.util.Arrays;
import java.util.List;
import java.util.Set;
import java.util.stream.Stream;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;

/**
 * Holds the catalog enums to {@code contracts/openapi-v2.yaml}.
 *
 * <p>The spec is the authority and these constants are its shadow, so the expectations are read
 * from the spec rather than restated here. A renamed code, a reworded title or a dropped constant
 * fails on whichever side changed alone.
 */
class ErrorCatalogTest {

    private static final List<String> CATALOG_TYPES = List.of(
            "support.error.CommonError",
            "diary.internal.DiaryError",
            "relationship.internal.RelationshipError",
            "media.internal.MediaError",
            "notification.internal.NotificationError",
            "identity.internal.IdentityError");

    /**
     * Failures the servlet security chain can raise before any documented operation is matched.
     *
     * <p>{@code ACCESS_DENIED} answers an authenticated request to a path outside {@code
     * /api/v2/**} — {@code BasicSecurityHttpTest} pins it on {@code POST /health}. No documented
     * operation can return it, so publishing a problem schema for it would describe a response no
     * declared endpoint produces.
     */
    private static final Set<String> UNROUTED_CODES = Set.of("ACCESS_DENIED");

    private static final PublishedProblemContract PUBLISHED = PublishedProblemContract.load();

    @Test
    void assignsEveryErrorCodeToExactlyOneCatalogConstant() {
        assertThat(descriptors().map(ErrorDescriptor::code).toList()).doesNotHaveDuplicates();
    }

    @Test
    void publishesExactlyTheDocumentedSetOfErrorCodes() {
        Set<String> documented = PUBLISHED.byCode().keySet();

        assertThat(descriptors().map(ErrorDescriptor::code))
                .as("every catalog constant is published, and every published code is implemented")
                .containsExactlyInAnyOrderElementsOf(union(documented, UNROUTED_CODES));
    }

    @Test
    void declaresALogLevelForEveryFailure() {
        descriptors().forEach(error -> assertThat(error.logLevel())
                .as("logLevel of %s", error.code())
                .isNotNull());
    }

    @Nested
    class EveryRoutedFailure {

        @ParameterizedTest(name = "{0} keeps its published status")
        @MethodSource("com.woorisai.support.error.ErrorCatalogTest#routedDescriptors")
        void keepsItsPublishedStatus(String code, ErrorDescriptor error) {
            assertThat(error.status()).isEqualTo(published(code).status());
        }

        @ParameterizedTest(name = "{0} keeps its published title")
        @MethodSource("com.woorisai.support.error.ErrorCatalogTest#routedDescriptors")
        void keepsItsPublishedTitle(String code, ErrorDescriptor error) {
            assertThat(error.title()).isEqualTo(published(code).title());
        }

        @ParameterizedTest(name = "{0} keeps its published detail")
        @MethodSource("com.woorisai.support.error.ErrorCatalogTest#routedDescriptors")
        void keepsItsPublishedDetail(String code, ErrorDescriptor error) {
            assertThat(error.detail()).isEqualTo(published(code).detail());
        }

        // ApiProblem requires instance and NotificationApiProblem omits it. Which schema a code
        // extends is the whole meaning of exposesInstance, so it is read from the spec too.
        @ParameterizedTest(name = "{0} follows its published instance policy")
        @MethodSource("com.woorisai.support.error.ErrorCatalogTest#routedDescriptors")
        void followsItsPublishedInstancePolicy(String code, ErrorDescriptor error) {
            assertThat(error.exposesInstance()).isEqualTo(published(code).exposesInstance());
        }

        private PublishedProblem published(String code) {
            return PUBLISHED.byCode().get(code);
        }
    }

    static Stream<org.junit.jupiter.params.provider.Arguments> routedDescriptors() {
        return descriptors()
                .filter(error -> !UNROUTED_CODES.contains(error.code()))
                .map(error -> org.junit.jupiter.params.provider.Arguments.of(error.code(), error));
    }

    private static Set<String> union(Set<String> first, Set<String> second) {
        return Stream.concat(first.stream(), second.stream())
                .collect(java.util.stream.Collectors.toUnmodifiableSet());
    }

    private static Stream<ErrorDescriptor> descriptors() {
        return CATALOG_TYPES.stream().flatMap(ErrorCatalogTest::constantsOf);
    }

    @SuppressWarnings("unchecked")
    private static Stream<ErrorDescriptor> constantsOf(String packageSuffix) {
        Class<? extends ErrorDescriptor> type;
        try {
            type = (Class<? extends ErrorDescriptor>) Class.forName("com.woorisai." + packageSuffix);
        } catch (ClassNotFoundException exception) {
            throw new IllegalStateException(exception);
        }
        try {
            var values = type.getDeclaredMethod("values");
            values.setAccessible(true);
            return Arrays.stream((ErrorDescriptor[]) values.invoke(null));
        } catch (NoSuchMethodException | IllegalAccessException exception) {
            throw new IllegalStateException(exception);
        } catch (InvocationTargetException exception) {
            throw new IllegalStateException(exception.getCause());
        }
    }
}
