package com.woorisai.support.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.logging.LogLevel;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Guards how the single advice attributes framework failures to a controller.
 *
 * <p>Before this advice existed each controller had its own {@code assignableTypes} handler, so the
 * same {@code DataAccessException} became {@code DIARY_UNAVAILABLE} on one endpoint and
 * {@code MEDIA_UPLOADS_UNAVAILABLE} on another. A single advice sees one exception type and must not
 * collapse that distinction, nor invent a code for a controller that never published one.
 */
class ApiControllerAdviceTest {

    private enum FixtureError implements ErrorDescriptor {
        MAPPED_UNAVAILABLE(
                HttpStatus.SERVICE_UNAVAILABLE, "FIXTURE_UNAVAILABLE", "Fixture unavailable",
                "Fixture data is temporarily unavailable.", true),
        WITHOUT_INSTANCE(
                HttpStatus.SERVICE_UNAVAILABLE, "FIXTURE_NO_INSTANCE", "Fixture no instance",
                "Fixture omits instance.", false);

        private final HttpStatus status;
        private final String code;
        private final String title;
        private final String detail;
        private final boolean exposesInstance;

        FixtureError(
                HttpStatus status, String code, String title, String detail, boolean exposesInstance) {
            this.status = status;
            this.code = code;
            this.title = title;
            this.detail = detail;
            this.exposesInstance = exposesInstance;
        }

        @Override
        public HttpStatus status() {
            return status;
        }

        @Override
        public String code() {
            return code;
        }

        @Override
        public String title() {
            return title;
        }

        @Override
        public String detail() {
            return detail;
        }

        @Override
        public LogLevel logLevel() {
            return LogLevel.INFO;
        }

        @Override
        public boolean exposesInstance() {
            return exposesInstance;
        }
    }

    @RestController
    static class MappedController {

        @GetMapping("/fixture/mapped")
        String fail() {
            throw new DataAccessResourceFailureException("redacted");
        }
    }

    @RestController
    static class UnmappedController {

        @GetMapping("/fixture/unmapped")
        String fail() {
            throw new DataAccessResourceFailureException("redacted");
        }
    }

    @RestController
    static class WithoutInstanceController {

        @GetMapping("/fixture/no-instance")
        String fail() {
            throw new DataAccessResourceFailureException("redacted");
        }
    }

    private static final class Mapping implements HandlerFailures {

        private final Class<?> type;
        private final ErrorDescriptor error;

        private Mapping(Class<?> type, ErrorDescriptor error) {
            this.type = type;
            this.error = error;
        }

        @Override
        public Class<?> handlerType() {
            return type;
        }

        @Override
        public Optional<ErrorDescriptor> unavailable() {
            return Optional.of(error);
        }
    }

    @Test
    @DisplayName("매핑을 선언한 controller의 framework 실패는 그 module의 계약으로 응답한다")
    void reportsFrameworkFailureUnderTheDeclaringControllersContract() throws Exception {
        mvc().perform(get("/fixture/mapped"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("FIXTURE_UNAVAILABLE"))
                .andExpect(jsonPath("$.title").value("Fixture unavailable"))
                .andExpect(jsonPath("$.instance").value("/fixture/mapped"));
    }

    @Test
    @DisplayName("매핑이 없는 controller의 framework 실패는 다른 module의 코드로 새지 않는다")
    void doesNotBorrowAnotherModulesCodeForAnUnmappedController() {
        assertThat(catchFailure("/fixture/unmapped"))
                .as("an unmapped controller must not answer with another module's errorCode")
                .isInstanceOf(DataAccessResourceFailureException.class);
    }

    @Test
    @DisplayName("instance를 노출하지 않는 계약은 instance 없이 응답한다")
    void omitsInstanceWhenTheContractDoesNotExposeIt() throws Exception {
        mvc().perform(get("/fixture/no-instance"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.errorCode").value("FIXTURE_NO_INSTANCE"))
                .andExpect(jsonPath("$.instance").doesNotExist());
    }

    @Test
    @DisplayName("한 controller에 두 매핑을 등록하면 시작 시점에 거부한다")
    void rejectsDuplicateMappingsForOneController() {
        List<HandlerFailures> duplicated = List.of(
                new Mapping(MappedController.class, FixtureError.MAPPED_UNAVAILABLE),
                new Mapping(MappedController.class, FixtureError.WITHOUT_INSTANCE));

        assertThat(catchThrowable(() -> ApiErrorAdvice.of(duplicated.toArray(HandlerFailures[]::new))))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining(MappedController.class.getName());
    }

    private Throwable catchFailure(String path) {
        return catchThrowable(() -> mvc().perform(get(path)));
    }

    private static Throwable catchThrowable(ThrowingCallable callable) {
        try {
            callable.call();
            return null;
        } catch (Throwable throwable) {
            return unwrap(throwable);
        }
    }

    private static Throwable unwrap(Throwable throwable) {
        Throwable current = throwable;
        while (current instanceof jakarta.servlet.ServletException && current.getCause() != null) {
            current = current.getCause();
        }
        return current;
    }

    private interface ThrowingCallable {
        void call() throws Exception;
    }

    private MockMvc mvc() {
        return MockMvcBuilders.standaloneSetup(
                        new MappedController(),
                        new UnmappedController(),
                        new WithoutInstanceController())
                .setControllerAdvice(ApiErrorAdvice.of(
                        new Mapping(MappedController.class, FixtureError.MAPPED_UNAVAILABLE),
                        new Mapping(WithoutInstanceController.class, FixtureError.WITHOUT_INSTANCE)))
                .build();
    }
}
