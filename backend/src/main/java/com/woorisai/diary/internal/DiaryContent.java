package com.woorisai.diary.internal;

record DiaryEntryContent(String value) {

    private static final int MAXIMUM_CODE_POINTS = 1000;

    DiaryEntryContent {
        value = DiaryText.required(value, MAXIMUM_CODE_POINTS);
    }

    static DiaryEntryContent from(String value) {
        return new DiaryEntryContent(value);
    }
}

record DiaryCommentContent(String value) {

    private static final int MAXIMUM_CODE_POINTS = 500;

    DiaryCommentContent {
        value = DiaryText.required(value, MAXIMUM_CODE_POINTS);
    }

    static DiaryCommentContent from(String value) {
        return new DiaryCommentContent(value);
    }
}
