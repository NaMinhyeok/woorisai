package com.woorisai.diary.internal;

import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

interface DiaryEntryRepository extends JpaRepository<DiaryEntry, Long> {

    Page<DiaryEntry> findAllByDeletedAtIsNullOrderByCreatedAtDescIdDesc(Pageable pageable);

    Optional<DiaryEntry> findByIdAndDeletedAtIsNull(long id);

    // Comment creation used to be guarded by diary_entry_comment_entry_fk: deleting the
    // parent physically made an overlapping insert violate the key. Soft delete keeps the
    // row, so the key can never fire, and a plain read-then-insert is not equivalent --
    // the two statements leave a gap the deleter commits into.
    //
    // A shared lock on the live parent closes that gap. It does not write the parent, so
    // independent comments on one entry still commit concurrently; docs/domain/invariants.md
    // keeps that property deliberately. The caller must treat an empty result as a
    // conflict -- the lock alone does not stop the insert.
    @Lock(LockModeType.PESSIMISTIC_READ)
    @Query("select entry.id from DiaryEntry entry where entry.id = :id and entry.deletedAt is null")
    Optional<Long> lockLiveEntryForCommentCreation(@Param("id") long id);
}
