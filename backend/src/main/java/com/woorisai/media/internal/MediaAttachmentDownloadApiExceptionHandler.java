package com.woorisai.media.internal;

import jakarta.servlet.http.HttpServletRequest;
import java.net.URI;
import org.springframework.dao.DataAccessException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.TransactionException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice(assignableTypes = MediaAttachmentDownloadController.class)
class MediaAttachmentDownloadApiExceptionHandler {

    @ExceptionHandler({
            InvalidMediaAttachmentDownloadRequestException.class,
            InvalidMediaDownloadRequestException.class
    })
    ResponseEntity<ProblemDetail> invalidRequest(HttpServletRequest request) {
        return problem(
                HttpStatus.BAD_REQUEST,
                "Invalid media download request",
                "The media download request is invalid.",
                "INVALID_MEDIA_DOWNLOAD_REQUEST",
                request);
    }

    @ExceptionHandler(MediaAttachmentNotFoundException.class)
    ResponseEntity<ProblemDetail> notFound(HttpServletRequest request) {
        return problem(
                HttpStatus.NOT_FOUND,
                "Media attachment not found",
                "The media attachment was not found.",
                "MEDIA_ATTACHMENT_NOT_FOUND",
                request);
    }

    @ExceptionHandler({
            MediaAttachmentDownloadUnavailableException.class,
            MediaDownloadUnavailableException.class,
            DataAccessException.class,
            TransactionException.class
    })
    ResponseEntity<ProblemDetail> unavailable(HttpServletRequest request) {
        return problem(
                HttpStatus.SERVICE_UNAVAILABLE,
                "Media download unavailable",
                "Media download is temporarily unavailable.",
                "MEDIA_DOWNLOAD_UNAVAILABLE",
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
