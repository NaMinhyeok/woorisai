package com.woorisai.cutover;

import java.sql.SQLException;

public final class CutoverDataCopyMain {

    private CutoverDataCopyMain() {}

    public static void main(String[] arguments) {
        try {
            CutoverConfig config = CutoverConfig.fromEnvironment(arguments, System.getenv());
            DataCopyReport report = new CutoverDataCopy().execute(config);
            String outcome = report.committed() ? "committed" : "verified and rolled back";
            System.out.println("Woorisai cutover copy " + outcome + ".");
            report.rowCounts().forEach((table, count) ->
                    System.out.println(table + "=" + count));
        } catch (CutoverException exception) {
            Throwable cause = exception.getCause();
            if (cause instanceof SQLException sqlException) {
                System.err.println(
                        "Woorisai cutover copy failed with PostgreSQL state "
                                + safeSqlState(sqlException));
            } else {
                System.err.println("Woorisai cutover copy failed: " + exception.getMessage());
            }
            System.exit(1);
        } catch (RuntimeException exception) {
            System.err.println(
                    "Woorisai cutover copy failed unexpectedly; keep ingress blocked and verify target state.");
            System.exit(1);
        }
    }

    private static String safeSqlState(SQLException exception) {
        String state = exception.getSQLState();
        return state == null || !state.matches("[0-9A-Z]{5}") ? "unknown" : state;
    }
}
