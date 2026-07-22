package com.woorisai.identity.internal;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.net.URI;
import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.security.authentication.InternalAuthenticationServiceException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;
import tools.jackson.databind.ObjectMapper;

@Component
@RequiredArgsConstructor
class ApiSecurityProblemHandler implements AuthenticationEntryPoint, AccessDeniedHandler {

    private static final String BASIC_CHALLENGE = "Basic realm=\"woorisai\"";

    private final ObjectMapper objectMapper;

    @Override
    public void commence(
            HttpServletRequest request,
            HttpServletResponse response,
            AuthenticationException exception) throws IOException {
        if (exception instanceof InternalAuthenticationServiceException) {
            authenticationUnavailable(request, response);
            return;
        }

        response.setHeader(HttpHeaders.WWW_AUTHENTICATE, BASIC_CHALLENGE);
        write(
                request,
                response,
                HttpStatus.UNAUTHORIZED,
                "Authentication required",
                "Valid HTTP Basic participant credentials are required.",
                "AUTHENTICATION_REQUIRED");
    }

    @Override
    public void handle(
            HttpServletRequest request,
            HttpServletResponse response,
            org.springframework.security.access.AccessDeniedException exception)
            throws IOException {
        write(
                request,
                response,
                HttpStatus.FORBIDDEN,
                "Access denied",
                "Access to this resource is denied.",
                "ACCESS_DENIED");
    }

    private void authenticationUnavailable(
            HttpServletRequest request,
            HttpServletResponse response) throws IOException {
        write(
                request,
                response,
                HttpStatus.SERVICE_UNAVAILABLE,
                "Authentication unavailable",
                "Authentication is temporarily unavailable.",
                "AUTHENTICATION_UNAVAILABLE");
    }

    private void write(
            HttpServletRequest request,
            HttpServletResponse response,
            HttpStatus status,
            String title,
            String detail,
            String errorCode) throws IOException {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
        problem.setTitle(title);
        problem.setInstance(URI.create(request.getRequestURI()));
        problem.setProperty("errorCode", errorCode);

        response.setStatus(status.value());
        response.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);
        response.setHeader(
                HttpHeaders.CACHE_CONTROL,
                CacheControl.noStore().getHeaderValue());
        objectMapper.writeValue(response.getOutputStream(), problem);
    }
}
