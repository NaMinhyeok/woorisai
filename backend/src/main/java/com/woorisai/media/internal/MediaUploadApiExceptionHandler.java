package com.woorisai.media.internal;

import jakarta.servlet.http.HttpServletRequest;
import java.net.URI;
import org.springframework.dao.DataAccessException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.transaction.TransactionException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice(assignableTypes = MediaUploadController.class)
class MediaUploadApiExceptionHandler {

    @ExceptionHandler({
            InvalidMediaUploadHttpRequestException.class,
            MethodArgumentNotValidException.class,
            HttpMessageNotReadableException.class,
            InvalidMediaUploadRequestException.class,
            InvalidMediaUploadCompletionRequestException.class,
            MediaUploadContentRejectedException.class,
            InvalidMediaUploadDiscardRequestException.class
    })
    ResponseEntity<ProblemDetail> invalidRequest(HttpServletRequest request) {
        return problem(
                HttpStatus.BAD_REQUEST,
                "Invalid media upload request",
                "The media upload request is invalid.",
                "INVALID_MEDIA_UPLOAD_REQUEST",
                request);
    }

    @ExceptionHandler({
            MediaUploadCompletionForbiddenException.class,
            MediaUploadDiscardForbiddenException.class
    })
    ResponseEntity<ProblemDetail> forbidden(HttpServletRequest request) {
        return problem(
                HttpStatus.FORBIDDEN,
                "Media upload forbidden",
                "The media upload is not owned by the authenticated participant.",
                "MEDIA_UPLOAD_FORBIDDEN",
                request);
    }

    @ExceptionHandler({
            MediaUploadNotFoundException.class
    })
    ResponseEntity<ProblemDetail> notFound(HttpServletRequest request) {
        return problem(
                HttpStatus.NOT_FOUND,
                "Media upload not found",
                "The media upload or authorized parent was not found.",
                "MEDIA_UPLOAD_NOT_FOUND",
                request);
    }

    @ExceptionHandler({
            MediaUploadCompletionConflictException.class,
            MediaUploadDiscardConflictException.class
    })
    ResponseEntity<ProblemDetail> conflict(HttpServletRequest request) {
        return problem(
                HttpStatus.CONFLICT,
                "Media upload conflict",
                "The media upload cannot be processed in its current state.",
                "MEDIA_UPLOAD_CONFLICT",
                request);
    }

    @ExceptionHandler({
            MediaUploadsUnavailableHttpException.class,
            MediaUploadInitiationUnavailableException.class,
            MediaUploadCompletionUnavailableException.class,
            MediaUploadDiscardUnavailableException.class,
            DataAccessException.class,
            TransactionException.class
    })
    ResponseEntity<ProblemDetail> unavailable(HttpServletRequest request) {
        return problem(
                HttpStatus.SERVICE_UNAVAILABLE,
                "Media uploads unavailable",
                "Media uploads are temporarily unavailable.",
                "MEDIA_UPLOADS_UNAVAILABLE",
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
