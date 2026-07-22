package com.woorisai.cutover;

import java.nio.file.Path;
import java.util.Map;
import java.util.regex.Pattern;

record CutoverConfig(
        String jdbcUrl,
        String databaseUser,
        String databasePassword,
        String sourceSchema,
        String observedSourceCommit,
        String approvedSourceCommit,
        String slotOnePinHash,
        String slotTwoPinHash,
        Path r2InventoryPath,
        boolean commit,
        String commitApproval) {

    static final String COMMIT_APPROVAL = "COMMIT_WOORISAI_ONE_TRANSACTION_COPY";
    static final String EXPECTED_SOURCE_COMMIT =
            "94434a05474fb878e8d7debfb3a6a8926a1825d8";

    private static final Pattern SCHEMA_NAME = Pattern.compile("[a-z_][a-z0-9_]*");
    private static final Pattern COMMIT = Pattern.compile("[0-9a-f]{40}");
    private static final Pattern BCRYPT_PIN_HASH = Pattern.compile(
            "\\{bcrypt}\\$2[ayb]\\$(?:0[4-9]|[12]\\d|3[01])\\$[./A-Za-z0-9]{53}");

    CutoverConfig {
        jdbcUrl = required(jdbcUrl, "WOORISAI_CUTOVER_JDBC_URL");
        databaseUser = required(databaseUser, "WOORISAI_CUTOVER_DATABASE_USER");
        databasePassword = required(
                databasePassword,
                "WOORISAI_CUTOVER_DATABASE_PASSWORD");
        sourceSchema = required(sourceSchema, "WOORISAI_CUTOVER_SOURCE_SCHEMA");
        observedSourceCommit = required(
                observedSourceCommit,
                "WOORISAI_CUTOVER_OBSERVED_SOURCE_COMMIT");
        approvedSourceCommit = required(
                approvedSourceCommit,
                "WOORISAI_CUTOVER_APPROVED_SOURCE_COMMIT");
        slotOnePinHash = required(slotOnePinHash, "WOORISAI_CUTOVER_SLOT_1_PIN_HASH");
        slotTwoPinHash = required(slotTwoPinHash, "WOORISAI_CUTOVER_SLOT_2_PIN_HASH");
        if (r2InventoryPath == null) {
            throw new CutoverException("WOORISAI_CUTOVER_R2_INVENTORY_PATH is required");
        }
        if (!r2InventoryPath.isAbsolute()) {
            throw new CutoverException("The R2 inventory path must be absolute");
        }

        if (!SCHEMA_NAME.matcher(sourceSchema).matches() || "woorisai".equals(sourceSchema)) {
            throw new CutoverException("The source schema name is invalid");
        }
        if (!COMMIT.matcher(observedSourceCommit).matches()
                || !COMMIT.matcher(approvedSourceCommit).matches()
                || !observedSourceCommit.equals(approvedSourceCommit)
                || !EXPECTED_SOURCE_COMMIT.equals(approvedSourceCommit)) {
            throw new CutoverException(
                    "The observed and approved source commits do not match the reviewed baseline");
        }
        if (!BCRYPT_PIN_HASH.matcher(slotOnePinHash).matches()
                || !BCRYPT_PIN_HASH.matcher(slotTwoPinHash).matches()) {
            throw new CutoverException(
                    "Both participant credentials must be Spring-compatible bcrypt hashes");
        }
        if (commit && !COMMIT_APPROVAL.equals(commitApproval)) {
            throw new CutoverException(
                    "Commit mode requires the explicit one-transaction copy approval");
        }
    }

    static CutoverConfig fromEnvironment(String[] arguments, Map<String, String> environment) {
        boolean commit = parseMode(arguments);
        String inventoryPath = environment.get("WOORISAI_CUTOVER_R2_INVENTORY_PATH");
        return new CutoverConfig(
                environment.get("WOORISAI_CUTOVER_JDBC_URL"),
                environment.get("WOORISAI_CUTOVER_DATABASE_USER"),
                environment.get("WOORISAI_CUTOVER_DATABASE_PASSWORD"),
                environment.get("WOORISAI_CUTOVER_SOURCE_SCHEMA"),
                environment.get("WOORISAI_CUTOVER_OBSERVED_SOURCE_COMMIT"),
                environment.get("WOORISAI_CUTOVER_APPROVED_SOURCE_COMMIT"),
                environment.get("WOORISAI_CUTOVER_SLOT_1_PIN_HASH"),
                environment.get("WOORISAI_CUTOVER_SLOT_2_PIN_HASH"),
                inventoryPath == null ? null : Path.of(inventoryPath),
                commit,
                environment.get("WOORISAI_CUTOVER_COMMIT_APPROVAL"));
    }

    private static boolean parseMode(String[] arguments) {
        if (arguments == null || arguments.length == 0) {
            return false;
        }
        if (arguments.length == 1 && "--commit".equals(arguments[0])) {
            return true;
        }
        throw new CutoverException("The only supported argument is --commit");
    }

    private static String required(String value, String name) {
        if (value == null || value.isBlank()) {
            throw new CutoverException(name + " is required");
        }
        return value;
    }
}
