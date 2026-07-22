package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.BDDMockito.then;
import static org.mockito.Mockito.never;

import java.io.ByteArrayInputStream;
import java.net.URI;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.http.AbortableInputStream;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3Configuration;
import software.amazon.awssdk.services.s3.model.CopyObjectRequest;
import software.amazon.awssdk.services.s3.model.CopyObjectResponse;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.DeleteObjectResponse;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;

class R2MediaObjectStorageTest {

    private S3Client client;
    private S3Presigner presigner;
    private R2MediaObjectStorage storage;

    @BeforeEach
    void setUp() {
        client = Mockito.mock(S3Client.class);
        presigner = S3Presigner.builder()
                .endpointOverride(URI.create("https://synthetic-account.r2.invalid"))
                .region(Region.of("auto"))
                .credentialsProvider(StaticCredentialsProvider.create(
                        AwsBasicCredentials.create("fixture-access", "fixture-secret")))
                .serviceConfiguration(S3Configuration.builder()
                        .pathStyleAccessEnabled(true)
                        .build())
                .build();
        storage = new R2MediaObjectStorage(client, presigner, "fixture-bucket");
    }

    @AfterEach
    void closePresigner() {
        presigner.close();
    }

    @Test
    void signsPrivatePutAndGetWithoutCallingTheNetwork() {
        URI upload = storage.presignUpload(new UploadPresignRequest(
                "pending/" + UUID.randomUUID(),
                "image/png",
                8,
                MediaPolicy.PRIVATE_CACHE_CONTROL,
                900));
        URI download = storage.presignDownload(new DownloadPresignRequest(
                "media/" + UUID.randomUUID(), 300));

        assertThat(upload.getScheme()).isEqualTo("https");
        assertThat(upload.getHost()).isEqualTo("synthetic-account.r2.invalid");
        assertThat(upload.getRawQuery()).contains("X-Amz-Signature");
        assertThat(download.getScheme()).isEqualTo("https");
        assertThat(download.getRawQuery()).contains("X-Amz-Signature");
        then(client).shouldHaveNoInteractions();
    }

    @Test
    void inspectsOnlyTheBoundedPrefixAndCopiesWithPrivateMetadata() {
        byte[] png = new byte[] {
                (byte) 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a
        };
        given(client.headObject(any(HeadObjectRequest.class))).willReturn(
                HeadObjectResponse.builder()
                        .contentLength((long) png.length)
                        .contentType("IMAGE/PNG; charset=binary")
                        .build());
        given(client.getObject(any(GetObjectRequest.class))).willReturn(
                new ResponseInputStream<>(
                        GetObjectResponse.builder().build(),
                        AbortableInputStream.create(new ByteArrayInputStream(png))));
        given(client.copyObject(any(CopyObjectRequest.class)))
                .willReturn(CopyObjectResponse.builder().build());
        given(client.deleteObject(any(DeleteObjectRequest.class)))
                .willReturn(DeleteObjectResponse.builder().build());

        StoredMediaObject inspected = storage.inspect("pending/fixture");
        assertThat(inspected.size()).isEqualTo(png.length);
        assertThat(inspected.contentType()).isEqualTo("image/png");
        assertThat(inspected.initialBytes()).containsExactly(png);
        storage.copy(new MediaObjectCopy(
                "pending/fixture", "media/fixture", "image/png", "우리 사진.png"));
        storage.delete("pending/fixture");

        ArgumentCaptor<GetObjectRequest> range = ArgumentCaptor.forClass(GetObjectRequest.class);
        then(client).should().getObject(range.capture());
        assertThat(range.getValue().range()).isEqualTo("bytes=0-4095");

        ArgumentCaptor<CopyObjectRequest> copy = ArgumentCaptor.forClass(CopyObjectRequest.class);
        then(client).should().copyObject(copy.capture());
        assertThat(copy.getValue().sourceKey()).isEqualTo("pending/fixture");
        assertThat(copy.getValue().destinationKey()).isEqualTo("media/fixture");
        assertThat(copy.getValue().cacheControl()).isEqualTo(MediaPolicy.PRIVATE_CACHE_CONTROL);
        assertThat(copy.getValue().contentDisposition())
                .startsWith("inline; filename*=UTF-8''")
                .doesNotContain("우리 사진");
    }

    @Test
    void doesNotIssueAnInvalidRangeRequestForAnEmptyObject() {
        given(client.headObject(any(HeadObjectRequest.class))).willReturn(
                HeadObjectResponse.builder()
                        .contentLength(0L)
                        .contentType("image/png")
                        .build());

        StoredMediaObject inspected = storage.inspect("pending/empty");

        assertThat(inspected.size()).isZero();
        assertThat(inspected.initialBytes()).isEmpty();
        then(client).should(never()).getObject(any(GetObjectRequest.class));
    }

    @Test
    void capsTheInspectedPrefixAtTheStoredObjectContract() {
        byte[] objectBytes = new byte[StoredMediaObject.MAXIMUM_INITIAL_BYTES + 1];
        given(client.headObject(any(HeadObjectRequest.class))).willReturn(
                HeadObjectResponse.builder()
                        .contentLength((long) objectBytes.length)
                        .contentType("image/png")
                        .build());
        given(client.getObject(any(GetObjectRequest.class))).willReturn(
                new ResponseInputStream<>(
                        GetObjectResponse.builder().build(),
                        AbortableInputStream.create(new ByteArrayInputStream(objectBytes))));

        StoredMediaObject inspected = storage.inspect("pending/large-prefix");

        assertThat(inspected.size()).isEqualTo(objectBytes.length);
        assertThat(inspected.initialBytes())
                .hasSize(StoredMediaObject.MAXIMUM_INITIAL_BYTES);
    }

    @Test
    void mapsProviderNotFoundWithoutExposingTheObjectKey() {
        given(client.headObject(any(HeadObjectRequest.class))).willThrow(
                NoSuchKeyException.builder().statusCode(404).message("missing").build());

        assertThatThrownBy(() -> storage.inspect("private/key"))
                .isInstanceOf(MediaObjectNotFoundException.class)
                .hasMessageNotContaining("private/key");
    }
}
