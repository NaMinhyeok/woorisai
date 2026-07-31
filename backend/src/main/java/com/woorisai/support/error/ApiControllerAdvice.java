package com.woorisai.support.error;

import jakarta.servlet.http.HttpServletRequest;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.logging.LogLevel;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.transaction.TransactionException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

// Module failures arrive as ApplicationException and carry their own contract; framework failures
// get theirs from the controller's HandlerFailures.
@RestControllerAdvice
class ApiControllerAdvice {

    private static final Logger log = LoggerFactory.getLogger(ApiControllerAdvice.class);

    private final Map<Class<?>, HandlerFailures> failuresByHandlerType;

    ApiControllerAdvice(Collection<HandlerFailures> handlerFailures) {
        Map<Class<?>, HandlerFailures> mappings = new HashMap<>();
        handlerFailures.forEach(failures -> {
            HandlerFailures previous = mappings.put(failures.handlerType(), failures);
            if (previous != null) {
                throw new IllegalStateException(
                        "Duplicate HandlerFailures for " + failures.handlerType().getName());
            }
        });
        this.failuresByHandlerType = Map.copyOf(mappings);
    }

    @ExceptionHandler(ApplicationException.class)
    ResponseEntity<ProblemDetail> handleApplicationException(
            ApplicationException exception, HttpServletRequest request) {
        return respond(exception.error(), exception, request);
    }

    @ExceptionHandler(HttpMediaTypeNotSupportedException.class)
    ResponseEntity<ProblemDetail> handleUnsupportedMediaType(
            HttpMediaTypeNotSupportedException exception, HttpServletRequest request) {
        return respond(CommonError.UNSUPPORTED_MEDIA_TYPE, exception, request);
    }

    @ExceptionHandler({
            HttpMessageNotReadableException.class,
            MethodArgumentNotValidException.class,
            MissingServletRequestParameterException.class,
            MethodArgumentTypeMismatchException.class
    })
    ResponseEntity<ProblemDetail> handleInvalidRequest(
            Exception exception, HandlerMethod handlerMethod, HttpServletRequest request)
            throws Exception {
        return respond(
                mappingFor(handlerMethod).flatMap(HandlerFailures::invalidRequest),
                exception,
                request);
    }

    @ExceptionHandler(OptimisticLockingFailureException.class)
    ResponseEntity<ProblemDetail> handleOptimisticLockingFailure(
            OptimisticLockingFailureException exception,
            HandlerMethod handlerMethod,
            HttpServletRequest request) throws Exception {
        return respond(
                mappingFor(handlerMethod).flatMap(HandlerFailures::conflict),
                exception,
                request);
    }

    @ExceptionHandler({DataAccessException.class, TransactionException.class})
    ResponseEntity<ProblemDetail> handleDataAccessFailure(
            Exception exception, HandlerMethod handlerMethod, HttpServletRequest request)
            throws Exception {
        return respond(
                mappingFor(handlerMethod).flatMap(HandlerFailures::unavailable),
                exception,
                request);
    }

    private Optional<HandlerFailures> mappingFor(HandlerMethod handlerMethod) {
        if (handlerMethod == null) {
            return Optional.empty();
        }
        return Optional.ofNullable(failuresByHandlerType.get(handlerMethod.getBeanType()));
    }

    private ResponseEntity<ProblemDetail> respond(
            Optional<ErrorDescriptor> error, Exception exception, HttpServletRequest request)
            throws Exception {
        if (error.isEmpty()) {
            // Rethrow instead of guessing: reporting this under another module's code would break
            // the published contract silently.
            throw exception;
        }
        return respond(error.get(), exception, request);
    }

    private ResponseEntity<ProblemDetail> respond(
            ErrorDescriptor error, Exception exception, HttpServletRequest request) {
        record(error, exception);
        return ApiProblems.response(error, request.getRequestURI());
    }

    // Logs the type and code only. Request bodies, participant data and media URLs must not reach
    // the log.
    private void record(ErrorDescriptor error, Exception exception) {
        String type = exception.getClass().getSimpleName();
        if (error.logLevel() == LogLevel.ERROR) {
            log.error("{} -> {}", type, error.code(), exception);
            return;
        }
        if (error.logLevel() == LogLevel.WARN) {
            log.warn("{} -> {}", type, error.code());
            return;
        }
        log.info("{} -> {}", type, error.code());
    }
}
