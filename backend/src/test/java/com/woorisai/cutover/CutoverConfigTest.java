package com.woorisai.cutover;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.HashMap;
import java.util.Map;
import org.junit.jupiter.api.Test;

class CutoverConfigTest {

    private static final String SOURCE_COMMIT = "94434a05474fb878e8d7debfb3a6a8926a1825d8";
    private static final String SYNTHETIC_PIN_HASH =
            "{bcrypt}$2a$10$" + "A".repeat(53);

    @Test
    void noArgumentSelectsRollbackOnlyDryRun() {
        CutoverConfig config = CutoverConfig.fromEnvironment(new String[0], environment());

        assertThat(config.commit()).isFalse();
    }

    @Test
    void commitNeedsBothTheArgumentAndIndependentApprovalInput() {
        assertThatThrownBy(() -> CutoverConfig.fromEnvironment(
                new String[] {"--commit"}, environment()))
                .isInstanceOf(CutoverException.class)
                .hasMessageContaining("explicit one-transaction copy approval");

        Map<String, String> approved = environment();
        approved.put("WOORISAI_CUTOVER_COMMIT_APPROVAL", CutoverConfig.COMMIT_APPROVAL);
        assertThat(CutoverConfig.fromEnvironment(new String[] {"--commit"}, approved).commit())
                .isTrue();
    }

    @Test
    void plaintextOrUnknownCredentialFormatsAreRejected() {
        Map<String, String> invalid = environment();
        invalid.put("WOORISAI_CUTOVER_SLOT_1_PIN_HASH", "not-a-password-encoder-hash");

        assertThatThrownBy(() -> CutoverConfig.fromEnvironment(new String[0], invalid))
                .isInstanceOf(CutoverException.class)
                .hasMessageContaining("bcrypt hashes");
    }

    private static Map<String, String> environment() {
        Map<String, String> values = new HashMap<>();
        values.put("WOORISAI_CUTOVER_JDBC_URL", "jdbc:postgresql://localhost/isolated-rehearsal");
        values.put("WOORISAI_CUTOVER_DATABASE_USER", "synthetic-operator");
        values.put("WOORISAI_CUTOVER_DATABASE_PASSWORD", "synthetic-database-password");
        values.put("WOORISAI_CUTOVER_SOURCE_SCHEMA", "legacy");
        values.put("WOORISAI_CUTOVER_OBSERVED_SOURCE_COMMIT", SOURCE_COMMIT);
        values.put("WOORISAI_CUTOVER_APPROVED_SOURCE_COMMIT", SOURCE_COMMIT);
        values.put("WOORISAI_CUTOVER_SLOT_1_PIN_HASH", SYNTHETIC_PIN_HASH);
        values.put("WOORISAI_CUTOVER_SLOT_2_PIN_HASH", SYNTHETIC_PIN_HASH);
        values.put("WOORISAI_CUTOVER_R2_INVENTORY_PATH", "/private/rehearsal/inventory.tsv");
        return values;
    }
}
