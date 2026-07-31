package com.woorisai.support.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.boot.logging.LogLevel;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

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

    // A record cannot declare an accessor that collides with the interface method it implements.
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
    void reportsAFrameworkFailureUnderTheContractOfTheControllerThatRaisedIt() throws Exception {
        mvc().perform(get("/fixture/mapped"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(content().contentTypeCompatibleWith("application/problem+json"))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(jsonPath("$.errorCode").value("FIXTURE_UNAVAILABLE"))
                .andExpect(jsonPath("$.title").value("Fixture unavailable"))
                .andExpect(jsonPath("$.instance").value("/fixture/mapped"));
    }

    // One advice sees a single exception type where per-controller advices used to publish different
    // codes, so an unmapped controller must not answer with a code belonging to another module.
    @Test
    void rethrowsRatherThanBorrowingAnotherModulesCodeForAnUnmappedController() {
        assertThat(catchThrowable(() -> mvc().perform(get("/fixture/unmapped"))))
                .isInstanceOf(DataAccessResourceFailureException.class);
    }

    @Test
    void omitsInstanceWhenTheContractDoesNotExposeIt() throws Exception {
        mvc().perform(get("/fixture/no-instance"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.errorCode").value("FIXTURE_NO_INSTANCE"))
                .andExpect(jsonPath("$.instance").doesNotExist());
    }

    @Test
    void rejectsTwoMappingsForTheSameControllerAtConstruction() {
        List<HandlerFailures> duplicated = List.of(
                new Mapping(MappedController.class, FixtureError.MAPPED_UNAVAILABLE),
                new Mapping(MappedController.class, FixtureError.WITHOUT_INSTANCE));

        assertThat(catchThrowable(() -> ApiErrorAdvice.of(duplicated.toArray(HandlerFailures[]::new))))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining(MappedController.class.getName());
    }

    private static Throwable catchThrowable(ThrowingCallable callable) {
        try {
            callable.call();
            return null;
        } catch (Throwable throwable) {
            return unwrap(throwable);
        }
    }

    // MockMvc wraps a rethrown handler exception in a ServletException.
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
