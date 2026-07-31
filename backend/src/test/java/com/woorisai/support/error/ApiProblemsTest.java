package com.woorisai.support.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

import java.util.Optional;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.logging.LogLevel;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.json.JsonMapper;

/**
 * Pins the serialized key set of an error body.
 *
 * <p>{@code contracts/openapi-v2.yaml} declares {@code additionalProperties: false} on both problem
 * schemas, and {@code NotificationApiProblem} leaves {@code instance} out of its properties. So the
 * rendered JSON must carry exactly the published keys — an extra key, or an empty {@code instance}
 * string standing in for an absent one, breaks the contract just as a missing key would.
 *
 * <p>The assertions run against a rendered HTTP response rather than a bare object mapper, because
 * {@code ProblemDetail} only unwraps its extension properties under the web serialization setup.
 * {@code type} is absent from the rendered keys: it keeps its {@code about:blank} default, which the
 * serializer omits, and the published schemas do not require it.
 */
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

    @Test
    @DisplayName("instance를 노출하는 계약은 ApiProblem의 key만 직렬화한다")
    void serializesExactlyTheApiProblemKeys() throws Exception {
        assertThat(keysOf("/fixture/with-instance"))
                .containsExactlyInAnyOrder("title", "status", "detail", "instance", "errorCode");
    }

    @Test
    @DisplayName("instance를 노출하지 않는 계약은 instance key 자체를 직렬화하지 않는다")
    void omitsTheInstanceKeyEntirely() throws Exception {
        assertThat(keysOf("/fixture/without-instance"))
                .as("an empty instance string would still violate NotificationApiProblem")
                .containsExactlyInAnyOrder("title", "status", "detail", "errorCode");
    }

    @Test
    @DisplayName("응답은 problem+json과 no-store를 유지한다")
    void keepsProblemJsonAndNoStore() {
        var response = ApiProblems.response(Fixture.WITH_INSTANCE, "/api/v2/fixtures");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        assertThat(response.getHeaders().getContentType()).hasToString("application/problem+json");
        assertThat(response.getHeaders().getCacheControl()).isEqualTo("no-store");
    }

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
