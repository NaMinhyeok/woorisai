package com.woorisai.testing;

import org.testcontainers.postgresql.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

public final class WoorisaiPostgresContainer {

    private static final DockerImageName IMAGE = DockerImageName.parse(
            "postgres:18.4-alpine@sha256:"
                    + "9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15")
            .asCompatibleSubstituteFor("postgres");

    private WoorisaiPostgresContainer() {}

    public static PostgreSQLContainer create() {
        return new PostgreSQLContainer(IMAGE)
                .withDatabaseName("woorisai")
                .withUsername("woorisai_test")
                .withPassword("woorisai_test");
    }
}
