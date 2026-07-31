package com.woorisai.relationship.internal;

import com.woorisai.support.error.ApplicationException;

final class InvalidRelationshipRequestException extends ApplicationException {

    InvalidRelationshipRequestException() {
        super(RelationshipError.INVALID_REQUEST, "Relationship request is invalid");
    }
}

final class RelationshipNotFoundException extends ApplicationException {

    RelationshipNotFoundException() {
        super(RelationshipError.NOT_FOUND, "Relationship resource was not found");
    }
}

final class RelationshipForbiddenException extends ApplicationException {

    RelationshipForbiddenException() {
        super(RelationshipError.FORBIDDEN, "Relationship resource is forbidden");
    }
}

final class RelationshipConflictException extends ApplicationException {

    RelationshipConflictException() {
        super(RelationshipError.CONFLICT, "Relationship request conflicts with current state");
    }

    RelationshipConflictException(Throwable cause) {
        super(RelationshipError.CONFLICT, "Relationship request conflicts with current state", cause);
    }
}

final class RelationshipUnavailableException extends ApplicationException {

    RelationshipUnavailableException() {
        super(RelationshipError.UNAVAILABLE, "Relationship data is unavailable");
    }

    RelationshipUnavailableException(Throwable cause) {
        super(RelationshipError.UNAVAILABLE, "Relationship data is unavailable", cause);
    }
}
