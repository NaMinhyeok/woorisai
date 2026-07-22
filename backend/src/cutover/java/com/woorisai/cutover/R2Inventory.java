package com.woorisai.cutover;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

final class R2Inventory {

    private static final String HEADER = "object_key\tcontent_type\tsize\tetag";

    private final Map<String, InventoryObject> objects;

    private R2Inventory(Map<String, InventoryObject> objects) {
        this.objects = Map.copyOf(objects);
    }

    static R2Inventory read(Path path) {
        if (!Files.isRegularFile(path, LinkOption.NOFOLLOW_LINKS)) {
            throw new CutoverException("The R2 inventory must be a regular, non-symlink file");
        }
        try {
            List<String> lines = Files.readAllLines(path, StandardCharsets.UTF_8);
            if (lines.isEmpty() || !HEADER.equals(lines.getFirst())) {
                throw new CutoverException("The R2 inventory header is invalid");
            }
            Map<String, InventoryObject> objects = new HashMap<>();
            for (int index = 1; index < lines.size(); index++) {
                String line = lines.get(index);
                if (line.isEmpty()) {
                    throw invalidLine(index + 1);
                }
                String[] fields = line.split("\\t", -1);
                if (fields.length != 4
                        || invalidText(fields[0])
                        || invalidText(fields[1])
                        || invalidText(fields[3])) {
                    throw invalidLine(index + 1);
                }
                long size;
                try {
                    size = Long.parseLong(fields[2]);
                } catch (NumberFormatException exception) {
                    throw invalidLine(index + 1);
                }
                if (size <= 0) {
                    throw invalidLine(index + 1);
                }
                InventoryObject object = new InventoryObject(fields[1], size, normalizeEtag(fields[3]));
                if (objects.putIfAbsent(fields[0], object) != null) {
                    throw new CutoverException("The R2 inventory contains a duplicate object key");
                }
            }
            return new R2Inventory(objects);
        } catch (IOException exception) {
            throw new CutoverException("The R2 inventory could not be read", exception);
        }
    }

    void verify(String objectKey, String contentType, long size, String etag) {
        InventoryObject object = objects.get(objectKey);
        if (object == null
                || !object.contentType().equals(contentType)
                || object.size() != size
                || !object.etag().equals(normalizeEtag(etag))) {
            throw new CutoverException("An attached R2 object failed inventory verification");
        }
    }

    private static boolean invalidText(String value) {
        return value.isBlank()
                || value.codePoints().anyMatch(character -> character < 0x20 || character == 0x7f);
    }

    private static String normalizeEtag(String value) {
        if (value == null) {
            return "";
        }
        String normalized = value.strip();
        if (normalized.length() >= 2
                && normalized.startsWith("\"")
                && normalized.endsWith("\"")) {
            return normalized.substring(1, normalized.length() - 1);
        }
        return normalized;
    }

    private static CutoverException invalidLine(int lineNumber) {
        return new CutoverException("The R2 inventory is invalid at line " + lineNumber);
    }

    private record InventoryObject(String contentType, long size, String etag) {}
}
