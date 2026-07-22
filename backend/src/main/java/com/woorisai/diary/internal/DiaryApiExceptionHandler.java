package com.woorisai.diary.internal;

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

@RestControllerAdvice(assignableTypes = DiaryController.class)
class DiaryApiExceptionHandler {

    @ExceptionHandler({
            InvalidDiaryRequestException.class,
            HttpMessageNotReadableException.class,
            MissingServletRequestParameterException.class,
            MethodArgumentTypeMismatchException.class
    })
    ResponseEntity<ProblemDetail> invalidRequest(HttpServletRequest request) {
        return problem(
                HttpStatus.BAD_REQUEST,
                "Invalid diary request",
                "The diary request is invalid.",
                "INVALID_DIARY_REQUEST",
                request);
    }

    @ExceptionHandler({DiaryEntryNotFoundException.class, DiaryCommentNotFoundException.class})
    ResponseEntity<ProblemDetail> notFound(HttpServletRequest request) {
        return problem(
                HttpStatus.NOT_FOUND,
                "Diary resource not found",
                "The requested diary resource was not found.",
                "DIARY_NOT_FOUND",
                request);
    }

    @ExceptionHandler(DiaryMutationForbiddenException.class)
    ResponseEntity<ProblemDetail> forbidden(HttpServletRequest request) {
        return problem(
                HttpStatus.FORBIDDEN,
                "Diary mutation forbidden",
                "Only the author can change this diary resource.",
                "DIARY_FORBIDDEN",
                request);
    }

    @ExceptionHandler({DiaryConflictException.class, OptimisticLockingFailureException.class})
    ResponseEntity<ProblemDetail> conflict(HttpServletRequest request) {
        return problem(
                HttpStatus.CONFLICT,
                "Diary conflict",
                "The diary request conflicts with current state.",
                "DIARY_CONFLICT",
                request);
    }

    @ExceptionHandler({
            DiaryUnavailableException.class,
            DataAccessException.class,
            TransactionException.class
    })
    ResponseEntity<ProblemDetail> unavailable(HttpServletRequest request) {
        return problem(
                HttpStatus.SERVICE_UNAVAILABLE,
                "Diary unavailable",
                "Diary data is temporarily unavailable.",
                "DIARY_UNAVAILABLE",
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
