package com.woorisai.calendar.internal;

import com.woorisai.support.error.ApplicationException;
import com.woorisai.support.error.ErrorDescriptor;
import com.woorisai.support.error.HandlerFailures;
import java.util.Optional;
import lombok.Getter;
import lombok.experimental.Accessors;
import org.springframework.boot.logging.LogLevel;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Getter
@Accessors(fluent = true)
enum CalendarError implements ErrorDescriptor {
    INVALID(HttpStatus.BAD_REQUEST, "INVALID_CALENDAR_REQUEST", "Invalid calendar request"),
    NOT_FOUND(HttpStatus.NOT_FOUND, "CALENDAR_NOT_FOUND", "Calendar event not found"),
    FORBIDDEN(HttpStatus.FORBIDDEN, "CALENDAR_FORBIDDEN", "Calendar mutation forbidden"),
    CONFLICT(HttpStatus.CONFLICT, "CALENDAR_CONFLICT", "Calendar conflict"),
    UNAVAILABLE(HttpStatus.SERVICE_UNAVAILABLE, "CALENDAR_UNAVAILABLE", "Calendar unavailable");

    private final HttpStatus status;
    private final String code;
    private final String title;
    private final String detail;
    private final LogLevel logLevel;

    CalendarError(HttpStatus status, String code, String title) {
        this.status = status;
        this.code = code;
        this.title = title;
        this.detail = title + ".";
        this.logLevel = status == HttpStatus.SERVICE_UNAVAILABLE ? LogLevel.WARN : LogLevel.INFO;
    }
}

class InvalidCalendarRequestException extends ApplicationException {
    InvalidCalendarRequestException() { super(CalendarError.INVALID, "Invalid calendar request"); }
}
class CalendarNotFoundException extends ApplicationException {
    CalendarNotFoundException() { super(CalendarError.NOT_FOUND, "Calendar event not found"); }
}
class CalendarForbiddenException extends ApplicationException {
    CalendarForbiddenException() { super(CalendarError.FORBIDDEN, "Calendar mutation forbidden"); }
}
class CalendarConflictException extends ApplicationException {
    CalendarConflictException(Throwable cause) { super(CalendarError.CONFLICT, "Calendar conflict", cause); }
}
class CalendarUnavailableException extends ApplicationException {
    CalendarUnavailableException() { super(CalendarError.UNAVAILABLE, "Calendar unavailable"); }
}

@Component
class CalendarHandlerFailures implements HandlerFailures {
    public Class<?> handlerType() { return CalendarController.class; }
    public Optional<ErrorDescriptor> invalidRequest() { return Optional.of(CalendarError.INVALID); }
    public Optional<ErrorDescriptor> conflict() { return Optional.of(CalendarError.CONFLICT); }
    public Optional<ErrorDescriptor> unavailable() { return Optional.of(CalendarError.UNAVAILABLE); }
}
