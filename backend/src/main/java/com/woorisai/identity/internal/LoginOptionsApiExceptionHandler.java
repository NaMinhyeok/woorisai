package com.woorisai.identity.internal;

import com.woorisai.participant.ParticipantDirectory.ParticipantPairUnavailableException;
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

@RestControllerAdvice(assignableTypes = LoginOptionsController.class)
class LoginOptionsApiExceptionHandler {

    @ExceptionHandler({
            ParticipantPairUnavailableException.class,
            DataAccessException.class,
            TransactionException.class
    })
    ResponseEntity<ProblemDetail> loginOptionsUnavailable(HttpServletRequest request) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.SERVICE_UNAVAILABLE,
                "The participant login options are temporarily unavailable.");
        problem.setTitle("Login options unavailable");
        problem.setInstance(URI.create(request.getRequestURI()));
        problem.setProperty("errorCode", "LOGIN_OPTIONS_UNAVAILABLE");

        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .cacheControl(CacheControl.noStore())
                .body(problem);
    }
}
