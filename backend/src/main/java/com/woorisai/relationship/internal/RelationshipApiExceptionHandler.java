package com.woorisai.relationship.internal;

import jakarta.servlet.http.HttpServletRequest;
import java.net.URI;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.transaction.TransactionException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

@RestControllerAdvice(assignableTypes = RelationshipController.class)
class RelationshipApiExceptionHandler {

    @ExceptionHandler({
        InvalidRelationshipRequestException.class,
        HttpMessageNotReadableException.class,
        MissingServletRequestParameterException.class,
        MethodArgumentTypeMismatchException.class
    })
    ResponseEntity<ProblemDetail> invalidRequest(HttpServletRequest request) {
        return problem(
                HttpStatus.BAD_REQUEST,
                "Invalid relationship request",
                "The relationship request is invalid.",
                "INVALID_RELATIONSHIP_REQUEST",
                request);
    }

    @ExceptionHandler(RelationshipNotFoundException.class)
    ResponseEntity<ProblemDetail> notFound(HttpServletRequest request) {
        return problem(
                HttpStatus.NOT_FOUND,
                "Relationship resource not found",
                "The requested relationship resource was not found.",
                "RELATIONSHIP_NOT_FOUND",
                request);
    }

    @ExceptionHandler(RelationshipForbiddenException.class)
    ResponseEntity<ProblemDetail> forbidden(HttpServletRequest request) {
        return problem(
                HttpStatus.FORBIDDEN,
                "Relationship access denied",
                "Access to this relationship resource is denied.",
                "RELATIONSHIP_FORBIDDEN",
                request);
    }

    @ExceptionHandler({RelationshipConflictException.class, OptimisticLockingFailureException.class})
    ResponseEntity<ProblemDetail> conflict(HttpServletRequest request) {
        return problem(
                HttpStatus.CONFLICT,
                "Relationship conflict",
                "The relationship request conflicts with current state.",
                "RELATIONSHIP_CONFLICT",
                request);
    }

    @ExceptionHandler({
            RelationshipUnavailableException.class,
            DataAccessException.class,
            TransactionException.class
    })
    ResponseEntity<ProblemDetail> unavailable(HttpServletRequest request) {
        return problem(
                HttpStatus.SERVICE_UNAVAILABLE,
                "Relationship unavailable",
                "Relationship data is temporarily unavailable.",
                "RELATIONSHIP_UNAVAILABLE",
                request);
    }

    private ResponseEntity<ProblemDetail> problem(
            HttpStatus status,
            String title,
            String detail,
            String errorCode,
            HttpServletRequest request) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
        problem.setTitle(title);
        problem.setInstance(URI.create(request.getRequestURI()));
        problem.setProperty("errorCode", errorCode);
        return ResponseEntity.status(status)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .cacheControl(CacheControl.noStore())
                .body(problem);
    }
}
