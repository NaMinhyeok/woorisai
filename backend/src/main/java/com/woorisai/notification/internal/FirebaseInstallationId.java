package com.woorisai.notification.internal;

import java.util.regex.Pattern;

record FirebaseInstallationId(String value) {

    private static final Pattern VALID_VALUE = Pattern.compile("[A-Za-z0-9_-]{22}");

    FirebaseInstallationId {
        if (value == null || !VALID_VALUE.matcher(value).matches()) {
            throw new InvalidNotificationFidException();
        }
    }

    static FirebaseInstallationId parse(String value) {
        return new FirebaseInstallationId(value);
    }
}

final class InvalidNotificationFidException extends IllegalArgumentException {

    InvalidNotificationFidException() {
        super("Notification FID is invalid");
    }
}
