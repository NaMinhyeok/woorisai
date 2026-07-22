package com.woorisai.media;

import java.util.UUID;

public record AttachedMedia(
        UUID id,
        MediaKind kind,
        String fileName,
        String contentType,
        long byteSize) {}
