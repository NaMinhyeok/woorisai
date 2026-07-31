package com.woorisai.media.internal;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

class MediaContentSignatureTest {

    @Test
    void matchesEveryStoredImageTypeAgainstItsCanonicalMagicBytes() {
        assertThat(MediaContentSignature.matches(
                        "image/jpeg", bytes(0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46)))
                .isTrue();
        assertThat(MediaContentSignature.matches(
                        "image/png",
                        bytes(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00)))
                .isTrue();
        assertThat(MediaContentSignature.matches("image/webp", riffWebpHeader())).isTrue();
    }

    @Test
    void matchesEveryStoredVideoTypeAgainstItsCanonicalContainerHeader() {
        assertThat(MediaContentSignature.matches("video/quicktime", ftyp("qt  "))).isTrue();
        assertThat(MediaContentSignature.matches("video/mp4", ftyp("isom"))).isTrue();
        assertThat(MediaContentSignature.matches("video/mp4", ftyp("mp42"))).isTrue();
        assertThat(MediaContentSignature.matches(
                        "video/webm", bytes(0x1a, 0x45, 0xdf, 0xa3, 0x01, 0x00, 0x00, 0x00)))
                .isTrue();
    }

    @Test
    void quicktimeBrandWinsEvenWhenListedAfterMp4CompatibleBrands() {
        byte[] header = ftyp("isom", "qt  ");
        assertThat(MediaContentSignature.matches("video/quicktime", header)).isTrue();
        assertThat(MediaContentSignature.matches("video/mp4", header)).isFalse();
    }

    @Test
    void rejectsADeclaredTypeThatContradictsTheStoredBytes() {
        assertThat(MediaContentSignature.matches("video/mp4", ftyp("qt  "))).isFalse();
        assertThat(MediaContentSignature.matches(
                        "image/png", bytes(0xff, 0xd8, 0xff, 0xe0)))
                .isFalse();
    }

    @Test
    void rejectsUnknownContainersIncludingFtyplessQuicktime() {
        // A legacy QuickTime file may open with a moov atom instead of ftyp; the signature
        // check deliberately rejects it rather than guessing.
        byte[] moovFirst = new byte[16];
        moovFirst[3] = 0x08;
        System.arraycopy("moov".getBytes(StandardCharsets.US_ASCII), 0, moovFirst, 4, 4);
        assertThat(MediaContentSignature.matches("video/quicktime", moovFirst)).isFalse();

        assertThat(MediaContentSignature.matches("video/mp4", new byte[0])).isFalse();
        assertThat(MediaContentSignature.matches("video/mp4", null)).isFalse();
        assertThat(MediaContentSignature.matches(null, ftyp("isom"))).isFalse();
    }

    // "RIFF" + payload size + "WEBP" chunk identifier.
    private static byte[] riffWebpHeader() {
        byte[] header = new byte[12];
        System.arraycopy("RIFF".getBytes(StandardCharsets.US_ASCII), 0, header, 0, 4);
        header[4] = 0x24;
        System.arraycopy("WEBP".getBytes(StandardCharsets.US_ASCII), 0, header, 8, 4);
        return header;
    }

    private static byte[] bytes(int... values) {
        byte[] result = new byte[values.length];
        for (int index = 0; index < values.length; index++) {
            result[index] = (byte) values[index];
        }
        return result;
    }

    // Minimal ISO base media header: size(4) + "ftyp" + major brand + compatible brands.
    private static byte[] ftyp(String... brands) {
        byte[] header = new byte[8 + brands.length * 4];
        header[3] = (byte) header.length;
        System.arraycopy("ftyp".getBytes(StandardCharsets.US_ASCII), 0, header, 4, 4);
        for (int index = 0; index < brands.length; index++) {
            byte[] brand = brands[index].getBytes(StandardCharsets.US_ASCII);
            System.arraycopy(brand, 0, header, 8 + index * 4, 4);
        }
        return header;
    }
}
