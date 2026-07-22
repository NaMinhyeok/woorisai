package com.woorisai.identity.internal;

import static org.springframework.security.web.servlet.util.matcher.PathPatternRequestMatcher.pathPattern;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.util.matcher.OrRequestMatcher;
import org.springframework.security.web.util.matcher.RequestMatcher;

@Configuration(proxyBeanMethods = false)
@EnableWebSecurity
class ApiSecurityConfiguration {

    private static final RequestMatcher PUBLIC_ENDPOINTS = new OrRequestMatcher(
            pathPattern(HttpMethod.GET, "/health"),
            pathPattern(HttpMethod.GET, "/api/v2/auth/login-options"));

    private static final RequestMatcher API_ENDPOINTS = pathPattern("/api/v2/**");

    @Bean
    @Order(1)
    SecurityFilterChain publicEndpointSecurityFilterChain(
            HttpSecurity http,
            ApiSecurityProblemHandler problems) throws Exception {
        return stateless(http)
                .securityMatcher(PUBLIC_ENDPOINTS)
                .httpBasic(AbstractHttpConfigurer::disable)
                .exceptionHandling(exceptions -> exceptions
                        .authenticationEntryPoint(problems)
                        .accessDeniedHandler(problems))
                .authorizeHttpRequests(requests -> requests.anyRequest().permitAll())
                .build();
    }

    @Bean
    @Order(2)
    SecurityFilterChain protectedEndpointSecurityFilterChain(
            HttpSecurity http,
            BasicParticipantAuthenticationProvider authenticationProvider,
            ApiSecurityProblemHandler problems) throws Exception {
        return stateless(http)
                .authenticationProvider(authenticationProvider)
                .httpBasic(basic -> basic.authenticationEntryPoint(problems))
                .exceptionHandling(exceptions -> exceptions
                        .authenticationEntryPoint(problems)
                        .accessDeniedHandler(problems))
                .authorizeHttpRequests(requests -> requests
                        .requestMatchers(API_ENDPOINTS)
                        .authenticated()
                        .anyRequest()
                        .denyAll())
                .build();
    }

    private HttpSecurity stateless(HttpSecurity http) throws Exception {
        return http
                .csrf(AbstractHttpConfigurer::disable)
                .requestCache(AbstractHttpConfigurer::disable)
                .formLogin(AbstractHttpConfigurer::disable)
                .logout(AbstractHttpConfigurer::disable)
                .sessionManagement(session ->
                        session.sessionCreationPolicy(SessionCreationPolicy.STATELESS));
    }
}
