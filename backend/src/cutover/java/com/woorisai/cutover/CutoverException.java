package com.woorisai.cutover;

final class CutoverException extends RuntimeException {

    CutoverException(String message) {
        super(message);
    }

    CutoverException(String message, Throwable cause) {
        super(message, cause);
    }
}
