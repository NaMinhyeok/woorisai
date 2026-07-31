package com.woorisai.identity.internal;

import com.woorisai.support.error.ApiProblems;
import com.woorisai.support.error.ErrorDescriptor;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.security.authentication.InternalAuthenticationServiceException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;
import tools.jackson.databind.ObjectMapper;

// Runs before any handler is resolved, so the response goes to the servlet directly rather than
// through a ResponseEntity. Only the body is shared with the controller advice.
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
            write(request, response, IdentityError.AUTHENTICATION_UNAVAILABLE);
            return;
        }

        response.setHeader(HttpHeaders.WWW_AUTHENTICATE, BASIC_CHALLENGE);
        write(request, response, IdentityError.AUTHENTICATION_REQUIRED);
    }

    @Override
    public void handle(
            HttpServletRequest request,
            HttpServletResponse response,
            org.springframework.security.access.AccessDeniedException exception)
            throws IOException {
        write(request, response, IdentityError.ACCESS_DENIED);
    }

    private void write(
            HttpServletRequest request,
            HttpServletResponse response,
            ErrorDescriptor error) throws IOException {
        ProblemDetail problem = ApiProblems.body(error, request.getRequestURI());

        response.setStatus(error.status().value());
        response.setContentType(MediaType.APPLICATION_PROBLEM_JSON_VALUE);
        response.setHeader(
                HttpHeaders.CACHE_CONTROL,
                CacheControl.noStore().getHeaderValue());
        objectMapper.writeValue(response.getOutputStream(), problem);
    }
}
