package com.woorisai.diary.internal;

import org.hibernate.exception.ConstraintViolationException;
import org.springframework.dao.DataIntegrityViolationException;

final class DiaryConstraintViolationClassifier {

    private static final String COMMENT_ENTRY_FOREIGN_KEY = "diary_entry_comment_entry_fk";

    private DiaryConstraintViolationClassifier() {}

    static boolean isDeletedEntryConflict(DataIntegrityViolationException exception) {
        Throwable cause = exception;
        while (cause != null) {
            if (cause instanceof ConstraintViolationException violation
                    && COMMENT_ENTRY_FOREIGN_KEY.equalsIgnoreCase(violation.getConstraintName())) {
                return true;
            }
            cause = cause.getCause();
        }
        return false;
    }
}
