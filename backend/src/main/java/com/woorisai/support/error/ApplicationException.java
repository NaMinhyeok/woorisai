package com.woorisai.support.error;

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

    // Several failures share one wire contract but not one cause, so the message stays narrower
    // than the published detail. Only error() reaches the client.
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
