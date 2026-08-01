package com.woorisai.diary.internal;

import com.woorisai.media.MediaAttachmentMutation.InvalidMediaAttachmentRequestException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentConflictException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentForbiddenException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentUnavailableException;
import com.woorisai.media.MediaAttachmentMutation.MediaUploadNotFoundException;

final class DiaryMediaFailures {

    private DiaryMediaFailures() {}

    static void translating(Runnable attachment) {
        try {
            attachment.run();
        } catch (InvalidMediaAttachmentRequestException exception) {
            throw new InvalidDiaryRequestException();
        } catch (MediaUploadNotFoundException exception) {
            throw new DiaryMediaUploadNotFoundException();
        } catch (MediaAttachmentForbiddenException exception) {
            throw new DiaryMediaForbiddenException();
        } catch (MediaAttachmentConflictException exception) {
            throw new DiaryConflictException();
        } catch (MediaAttachmentUnavailableException exception) {
            throw new DiaryUnavailableException(exception);
        }
    }
}
