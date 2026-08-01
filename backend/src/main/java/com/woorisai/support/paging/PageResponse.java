package com.woorisai.support.paging;

import java.util.List;
import java.util.function.Function;
import org.springframework.data.domain.Page;

/**
 * A page of API results and the metadata describing it.
 *
 * <p>Every paged endpoint answers in this shape so a client decodes paging once, whatever the
 * results are.
 */
public record PageResponse<T>(List<T> results, Paging paging) {

    public PageResponse {
        results = List.copyOf(results);
    }

    public static <S, T> PageResponse<T> of(Page<S> page, Function<S, T> toResult) {
        return new PageResponse<>(page.map(toResult).getContent(), Paging.of(page));
    }
}
