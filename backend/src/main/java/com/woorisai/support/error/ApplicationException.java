package com.woorisai.support.error;

/**
 * Failure that already knows its own wire contract.
 *
 * <p>Modules extend this so a single advice can map any failure to a response without knowing
 * which module raised it.
 */
public abstract class ApplicationException extends RuntimeException {

    private final transient ErrorDescriptor error;

    protected ApplicationException(ErrorDescriptor error) {
        super(error.detail());
        this.error = error;
    }

    protected ApplicationException(ErrorDescriptor error, Throwable cause) {
        super(error.detail(), cause);
        this.error = error;
    }

    /**
     * Keeps a narrower internal message than the published {@code detail}.
     *
     * <p>Several failures share one wire contract but not one cause. The message stays in logs and
     * stack traces; only {@link #error()} reaches the client.
     */
    protected ApplicationException(ErrorDescriptor error, String message) {
        super(message);
        this.error = error;
    }

    protected ApplicationException(ErrorDescriptor error, String message, Throwable cause) {
        super(message, cause);
        this.error = error;
    }

    public ErrorDescriptor error() {
        return error;
    }
}
