package com.woorisai.testing;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import com.networknt.schema.JsonSchema;
import com.networknt.schema.JsonSchemaFactory;
import com.networknt.schema.SchemaValidatorsConfig;
import com.networknt.schema.SpecVersion;
import com.networknt.schema.ValidationMessage;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.test.web.servlet.ResultMatcher;

/**
 * Validates a response body against the schema {@code contracts/openapi-v2.yaml} publishes for it.
 *
 * <p>Hand-picked {@code jsonPath} assertions only prove the fields they name. A response that
 * grows a field, drops a required one or changes a type still passes them, while the published
 * schemas set {@code additionalProperties: false} and the iOS client generates its types from
 * those schemas — so the drift surfaces as a decoding failure on the device instead of a red
 * build here.
 *
 * <p>Usage in a standalone MockMvc test:
 *
 * <pre>{@code
 * .andExpect(PublishedSchema.matches("DiaryEntryResponse"))
 * }</pre>
 */
public final class PublishedSchema {

    /** Set by the build so the spec is a declared input of the test task. */
    private static final String SPEC_PATH_PROPERTY = "woorisai.contract.openapi";

    private static final ObjectMapper YAML = new ObjectMapper(new YAMLFactory());
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final Map<String, JsonSchema> CACHE = new ConcurrentHashMap<>();

    private PublishedSchema() {}

    /** Asserts the response body satisfies the named published schema. */
    public static ResultMatcher matches(String schemaName) {
        return result -> assertMatches(
                schemaName,
                result.getResponse().getContentAsString(StandardCharsets.UTF_8));
    }

    /** Asserts a JSON document satisfies the named published schema. */
    public static void assertMatches(String schemaName, String json) {
        JsonNode body;
        try {
            body = JSON.readTree(json);
        } catch (IOException exception) {
            throw new IllegalStateException(
                    "Response is not JSON, so " + schemaName + " cannot be checked", exception);
        }
        Set<ValidationMessage> violations = schema(schemaName).validate(body);
        assertThat(violations)
                .as("%s violates the schema published for it in contracts/openapi-v2.yaml:%n%s",
                        schemaName, describe(violations))
                .isEmpty();
    }

    private static String describe(Set<ValidationMessage> violations) {
        return violations.stream()
                .map(ValidationMessage::getMessage)
                .sorted(Comparator.naturalOrder())
                .reduce("", (all, message) -> all + "  - " + message + System.lineSeparator());
    }

    /**
     * Compiles one component schema with the whole document as its resolution scope, so
     * {@code $ref} and {@code allOf} reach the rest of the contract.
     */
    private static JsonSchema schema(String schemaName) {
        return CACHE.computeIfAbsent(schemaName, name -> {
            JsonNode document = document();
            JsonNode declared = document.at("/components/schemas/" + name);
            if (declared.isMissingNode()) {
                throw new IllegalStateException(
                        "contracts/openapi-v2.yaml publishes no schema named " + name);
            }
            // The spec is OpenAPI 3.1, which is JSON Schema 2020-12.
            SchemaValidatorsConfig config = SchemaValidatorsConfig.builder().build();
            JsonNode resolvable = declared.deepCopy();
            ((com.fasterxml.jackson.databind.node.ObjectNode) resolvable)
                    .set("components", document.get("components"));
            return JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012)
                    .getSchema(resolvable, config);
        });
    }

    private static JsonNode document() {
        Path spec = specPath();
        try {
            return YAML.readTree(Files.readString(spec));
        } catch (IOException exception) {
            throw new IllegalStateException("Cannot read the published contract at " + spec, exception);
        }
    }

    private static Path specPath() {
        String configured = System.getProperty(SPEC_PATH_PROPERTY);
        if (configured == null || configured.isBlank()) {
            throw new IllegalStateException(
                    "System property " + SPEC_PATH_PROPERTY + " is not set; the build must point the "
                            + "test task at contracts/openapi-v2.yaml");
        }
        Path spec = Path.of(configured);
        if (!Files.isRegularFile(spec)) {
            throw new IllegalStateException("The published contract is missing at " + spec);
        }
        return spec;
    }

    /** Schema names this helper is expected to resolve; used by its own test. */
    static List<String> knownSchemaNames() {
        JsonNode schemas = document().at("/components/schemas");
        return java.util.stream.StreamSupport
                .stream(java.util.Spliterators.spliteratorUnknownSize(
                        schemas.fieldNames(), 0), false)
                .toList();
    }
}
