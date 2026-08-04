package com.woorisai.support.error;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.yaml.snakeyaml.Yaml;

/**
 * The published failure contract, read from {@code contracts/openapi-v2.yaml}.
 *
 * <p>The spec is the authority and the catalog enums are its shadow. Restating the spec in a Java
 * map only proves the copy agrees with itself, so this reads the real file: editing either side
 * alone fails the comparison.
 */
final class PublishedProblemContract {

    /** Set by the build so the spec is a declared input of the test task. */
    private static final String SPEC_PATH_PROPERTY = "woorisai.contract.openapi";

    private static final String BASE_WITH_INSTANCE = "ApiProblem";
    private static final String BASE_WITHOUT_INSTANCE = "NotificationApiProblem";

    private final Map<String, PublishedProblem> byCode;

    private PublishedProblemContract(Map<String, PublishedProblem> byCode) {
        this.byCode = Map.copyOf(byCode);
    }

    record PublishedProblem(
            String code,
            HttpStatus status,
            String title,
            String detail,
            boolean exposesInstance,
            String schemaName) {}

    static PublishedProblemContract load() {
        Map<String, Object> schemas = schemasOf(read());
        Map<String, PublishedProblem> byCode = new LinkedHashMap<>();
        schemas.forEach((schemaName, node) -> {
            PublishedProblem problem = problemOf(schemaName, node);
            if (problem == null) {
                return;
            }
            PublishedProblem previous = byCode.put(problem.code(), problem);
            if (previous != null) {
                throw new IllegalStateException(
                        "errorCode " + problem.code() + " is published by both "
                                + previous.schemaName() + " and " + schemaName);
            }
        });
        if (byCode.isEmpty()) {
            throw new IllegalStateException("The published contract declares no problem schema");
        }
        return new PublishedProblemContract(byCode);
    }

    Map<String, PublishedProblem> byCode() {
        return byCode;
    }

    /**
     * Reads a concrete problem schema, or returns null for anything that is not one.
     *
     * <p>A concrete problem extends one of the two problem bases and pins its published constants
     * as single-value enums. {@code allOf} is used elsewhere in the spec for unrelated composition,
     * so the base reference — not the shape — is what identifies a problem.
     */
    private static PublishedProblem problemOf(String schemaName, Object node) {
        if (!(node instanceof Map<?, ?> schema)
                || !(schema.get("allOf") instanceof List<?> allOf)
                || allOf.size() != 2
                || !(allOf.get(0) instanceof Map<?, ?> base)
                || !(allOf.get(1) instanceof Map<?, ?> overrides)) {
            return notAProblem(schemaName);
        }
        Boolean exposesInstance = switch (schemaNameOf(base.get("$ref"))) {
            case BASE_WITH_INSTANCE -> true;
            case BASE_WITHOUT_INSTANCE -> false;
            case null, default -> null;
        };
        if (exposesInstance == null
                || !(overrides.get("properties") instanceof Map<?, ?> properties)) {
            return notAProblem(schemaName);
        }
        String code = pinnedString(schemaName, properties, "errorCode");
        if (code == null) {
            throw new IllegalStateException(schemaName + " extends a problem base without pinning an errorCode");
        }
        return new PublishedProblem(
                code,
                pinnedStatus(schemaName, properties),
                pinnedString(schemaName, properties, "title"),
                pinnedString(schemaName, properties, "detail"),
                exposesInstance,
                schemaName);
    }

    /**
     * A schema that is not a concrete problem. The two bases are expected; any other schema named
     * {@code *Problem} means a published failure was declared in a shape this reader cannot see,
     * which would silently drop it from the comparison.
     */
    private static PublishedProblem notAProblem(String schemaName) {
        if (schemaName.endsWith("Problem")
                && !schemaName.equals(BASE_WITH_INSTANCE)
                && !schemaName.equals(BASE_WITHOUT_INSTANCE)) {
            throw new IllegalStateException(
                    schemaName + " is named as a problem but does not extend "
                            + BASE_WITH_INSTANCE + " or " + BASE_WITHOUT_INSTANCE);
        }
        return null;
    }

    private static HttpStatus pinnedStatus(String schemaName, Map<?, ?> properties) {
        Object pinned = pinnedValue(schemaName, properties, "status");
        if (!(pinned instanceof Integer status)) {
            throw new IllegalStateException(schemaName + " pins a non-integer status: " + pinned);
        }
        HttpStatus resolved = HttpStatus.resolve(status);
        if (resolved == null) {
            throw new IllegalStateException(schemaName + " pins unknown status " + status);
        }
        return resolved;
    }

    private static String pinnedString(String schemaName, Map<?, ?> properties, String property) {
        Object pinned = pinnedValue(schemaName, properties, property);
        if (pinned == null) {
            return null;
        }
        if (!(pinned instanceof String value)) {
            throw new IllegalStateException(
                    schemaName + " pins a non-string " + property + ": " + pinned);
        }
        return value;
    }

    /** A published constant is an {@code enum} of exactly one value; anything else is not pinned. */
    private static Object pinnedValue(String schemaName, Map<?, ?> properties, String property) {
        if (!(properties.get(property) instanceof Map<?, ?> declared)) {
            return null;
        }
        if (!(declared.get("enum") instanceof List<?> values)) {
            return null;
        }
        if (values.size() != 1) {
            throw new IllegalStateException(
                    schemaName + " pins " + values.size() + " values for " + property);
        }
        return values.getFirst();
    }

    private static String schemaNameOf(Object ref) {
        if (!(ref instanceof String value)) {
            return null;
        }
        int lastSeparator = value.lastIndexOf('/');
        return lastSeparator < 0 ? value : value.substring(lastSeparator + 1);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> schemasOf(Map<String, Object> document) {
        Object components = document.get("components");
        if (!(components instanceof Map<?, ?> section)
                || !(section.get("schemas") instanceof Map<?, ?> schemas)) {
            throw new IllegalStateException("The published contract declares no components.schemas");
        }
        return (Map<String, Object>) schemas;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> read() {
        Path spec = specPath();
        try (InputStream source = Files.newInputStream(spec)) {
            return (Map<String, Object>) new Yaml().load(source);
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
}
