package com.woorisai.relationship.internal;

import com.woorisai.media.MediaAttachmentMutation.InvalidMediaAttachmentRequestException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentConflictException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentForbiddenException;
import com.woorisai.media.MediaAttachmentMutation.MediaAttachmentUnavailableException;
import com.woorisai.media.MediaAttachmentMutation.MediaUploadNotFoundException;

final class RelationshipMediaFailures {

    private RelationshipMediaFailures() {}

    static void translating(Runnable attachment) {
        try {
            attachment.run();
        } catch (InvalidMediaAttachmentRequestException exception) {
            throw new InvalidRelationshipRequestException();
        } catch (MediaUploadNotFoundException exception) {
            throw new RelationshipNotFoundException();
        } catch (MediaAttachmentForbiddenException exception) {
            throw new RelationshipForbiddenException();
        } catch (MediaAttachmentConflictException exception) {
            throw new RelationshipConflictException();
        } catch (MediaAttachmentUnavailableException exception) {
            throw new RelationshipUnavailableException(exception);
        }
    }
}
