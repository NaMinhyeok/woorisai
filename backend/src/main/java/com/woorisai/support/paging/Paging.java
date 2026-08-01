package com.woorisai.support.paging;

import org.springframework.data.domain.Page;

/**
 * Page metadata as the API exposes it.
 *
 * <p>Page numbers are one-based on the wire while Spring Data counts from zero. Reading the
 * number off the page instead of echoing the request keeps that conversion in one place.
 */
public record Paging(int pageNumber, int pageSize, boolean hasNext, long totalCount) {

    public Paging {
        if (pageNumber < 1 || pageSize < 1 || totalCount < 0) {
            throw new IllegalArgumentException("Paging is invalid");
        }
    }

    public static Paging of(Page<?> page) {
        return new Paging(
                page.getNumber() + 1, page.getSize(), page.hasNext(), page.getTotalElements());
    }
}
