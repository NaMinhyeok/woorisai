package com.woorisai.relationship.internal;

final class InvalidRelationshipRequestException extends RuntimeException {

    InvalidRelationshipRequestException() {
        super("Relationship request is invalid");
    }
}

final class RelationshipNotFoundException extends RuntimeException {

    RelationshipNotFoundException() {
        super("Relationship resource was not found");
    }
}

final class RelationshipForbiddenException extends RuntimeException {

    RelationshipForbiddenException() {
        super("Relationship resource is forbidden");
    }
}

final class RelationshipConflictException extends RuntimeException {

    RelationshipConflictException() {
        super("Relationship request conflicts with current state");
    }

    RelationshipConflictException(Throwable cause) {
        super("Relationship request conflicts with current state", cause);
    }
}

final class RelationshipUnavailableException extends RuntimeException {

    RelationshipUnavailableException() {
        super("Relationship data is unavailable");
    }

    RelationshipUnavailableException(Throwable cause) {
        super("Relationship data is unavailable", cause);
    }
}
