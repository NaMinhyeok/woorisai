package com.woorisai.media.internal;

import java.nio.charset.StandardCharsets;
import java.util.Set;

final class MediaContentSignature {

    private static final Set<String> MP4_BRANDS = Set.of(
            "M4A ", "M4V ", "avc1", "dash",
            "iso2", "iso3", "iso4", "iso5", "iso6", "iso7", "iso8", "iso9",
            "isom", "mp41", "mp42");

    private MediaContentSignature() {}

    static boolean matches(String contentType, byte[] initialBytes) {
        return contentType != null
                && initialBytes != null
                && contentType.equals(detect(initialBytes));
    }

    private static String detect(byte[] bytes) {
        if (startsWith(bytes, 0xff, 0xd8, 0xff)) {
            return "image/jpeg";
        }
        if (startsWith(bytes, 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)) {
            return "image/png";
        }
        if (bytes.length >= 12
                && ascii(bytes, 0, 4).equals("RIFF")
                && ascii(bytes, 8, 4).equals("WEBP")) {
            return "image/webp";
        }
        if (startsWith(bytes, 0x1a, 0x45, 0xdf, 0xa3)) {
            return "video/webm";
        }
        if (bytes.length >= 12 && ascii(bytes, 4, 4).equals("ftyp")) {
            boolean mp4 = false;
            int limit = Math.min(bytes.length, 64);
            for (int index = 8; index + 4 <= limit; index += 4) {
                String brand = ascii(bytes, index, 4);
                if (brand.equals("qt  ")) {
                    return "video/quicktime";
                }
                if (MP4_BRANDS.contains(brand)) {
                    mp4 = true;
                }
            }
            if (mp4) {
                return "video/mp4";
            }
        }
        return null;
    }

    private static boolean startsWith(byte[] bytes, int... expected) {
        if (bytes.length < expected.length) {
            return false;
        }
        for (int index = 0; index < expected.length; index++) {
            if (Byte.toUnsignedInt(bytes[index]) != expected[index]) {
                return false;
            }
        }
        return true;
    }

    private static String ascii(byte[] bytes, int offset, int length) {
        return new String(bytes, offset, length, StandardCharsets.US_ASCII);
    }
}
