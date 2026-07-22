package com.woorisai.diary.internal;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

interface DiaryEntryRepository extends JpaRepository<DiaryEntry, Long> {

    Page<DiaryEntry> findAllByOrderByCreatedAtDescIdDesc(Pageable pageable);
}
