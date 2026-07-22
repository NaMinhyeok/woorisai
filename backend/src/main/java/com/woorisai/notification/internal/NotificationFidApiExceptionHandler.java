package com.woorisai.notification.internal;

import com.woorisai.notification.internal.NotificationFidService.NotificationFidUnavailableException;
import org.springframework.dao.DataAccessException;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.transaction.TransactionException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice(assignableTypes = NotificationFidController.class)
class NotificationFidApiExceptionHandler {

    private static final String INVALID_FID = "INVALID_NOTIFICATION_FID";
    private static final String FID_UNAVAILABLE = "NOTIFICATION_FID_UNAVAILABLE";

    @ExceptionHandler({InvalidNotificationFidException.class, HttpMessageNotReadableException.class})
    ResponseEntity<ProblemDetail> invalidFid() {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.BAD_REQUEST,
                "Request must contain one valid Firebase installation ID.");
        problem.setTitle("Invalid notification FID request");
        problem.setProperty("errorCode", INVALID_FID);
        return problem(HttpStatus.BAD_REQUEST, problem);
    }

    @ExceptionHandler({
            NotificationFidUnavailableException.class,
            DataAccessException.class,
            TransactionException.class
    })
    ResponseEntity<ProblemDetail> unavailable() {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.SERVICE_UNAVAILABLE,
                "Notification FID service is temporarily unavailable.");
        problem.setTitle("Notification FID service unavailable");
        problem.setProperty("errorCode", FID_UNAVAILABLE);
        return problem(HttpStatus.SERVICE_UNAVAILABLE, problem);
    }

    private ResponseEntity<ProblemDetail> problem(
            HttpStatus status,
            ProblemDetail problem) {
        return ResponseEntity.status(status)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .cacheControl(CacheControl.noStore())
                .body(problem);
    }
}
