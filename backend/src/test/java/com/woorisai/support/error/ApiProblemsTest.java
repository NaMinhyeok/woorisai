package com.woorisai.support.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.boot.logging.LogLevel;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.json.JsonMapper;

class ApiProblemsTest {

    private enum Fixture implements ErrorDescriptor {
        WITH_INSTANCE(true),
        WITHOUT_INSTANCE(false);

        private final boolean exposesInstance;

        Fixture(boolean exposesInstance) {
            this.exposesInstance = exposesInstance;
        }

        @Override
        public HttpStatus status() {
            return HttpStatus.SERVICE_UNAVAILABLE;
        }

        @Override
        public String code() {
            return "FIXTURE_CODE";
        }

        @Override
        public String title() {
            return "Fixture title";
        }

        @Override
        public String detail() {
            return "Fixture detail.";
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
    static class WithInstanceController {

        @GetMapping("/fixture/with-instance")
        String fail() {
            throw new DataAccessResourceFailureException("redacted");
        }
    }

    @RestController
    static class WithoutInstanceController {

        @GetMapping("/fixture/without-instance")
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

    private final JsonMapper mapper = JsonMapper.builder().build();

    // Both published schemas set additionalProperties: false, so an extra key breaks the contract as
    // surely as a missing one. "type" is absent because it keeps its about:blank default, which the
    // serializer omits and neither schema requires.
    @Test
    void serializesExactlyTheKeysOfTheApiProblemSchema() throws Exception {
        assertThat(keysOf("/fixture/with-instance"))
                .containsExactlyInAnyOrder("title", "status", "detail", "instance", "errorCode");
    }

    // An empty instance string would satisfy doesNotExist() on some paths yet still violate
    // NotificationApiProblem, so assert on the key set rather than the value.
    @Test
    void omitsTheInstanceKeyEntirelyForTheNotificationSchema() throws Exception {
        assertThat(keysOf("/fixture/without-instance"))
                .containsExactlyInAnyOrder("title", "status", "detail", "errorCode");
    }

    @Test
    void answersWithProblemJsonAndNoStore() {
        var response = ApiProblems.response(Fixture.WITH_INSTANCE, "/api/v2/fixtures");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        assertThat(response.getHeaders().getContentType()).hasToString("application/problem+json");
        assertThat(response.getHeaders().getCacheControl()).isEqualTo("no-store");
    }

    // Rendered through MockMvc because ProblemDetail only unwraps its extension properties under the
    // web serialization setup; a bare mapper nests them under "properties".
    private Iterable<String> keysOf(String path) throws Exception {
        String json = MockMvcBuilders.standaloneSetup(
                        new WithInstanceController(), new WithoutInstanceController())
                .setControllerAdvice(ApiErrorAdvice.of(
                        new Mapping(WithInstanceController.class, Fixture.WITH_INSTANCE),
                        new Mapping(WithoutInstanceController.class, Fixture.WITHOUT_INSTANCE)))
                .build()
                .perform(get(path))
                .andReturn()
                .getResponse()
                .getContentAsString();

        return mapper.readTree(json).propertyNames();
    }
}
