// VN Reader — minimal C API over the RARLAB unrar library (dll.cpp API).
// Exposed to Swift. Keep this header plain C (no wchar_t, no packed structs).
#ifndef VNRAR_H
#define VNRAR_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Result codes (mirror ERAR_* from unrar dll.hpp).
enum {
  VNRAR_OK = 0,
  VNRAR_END = 10,
  VNRAR_NO_MEMORY = 11,
  VNRAR_BAD_DATA = 12,
  VNRAR_BAD_ARCHIVE = 13,
  VNRAR_UNKNOWN_FORMAT = 14,
  VNRAR_EOPEN = 15,
  VNRAR_ECREATE = 16,
  VNRAR_ECLOSE = 17,
  VNRAR_EREAD = 18,
  VNRAR_EWRITE = 19,
  VNRAR_SMALL_BUF = 20,
  VNRAR_UNKNOWN = 21,
  VNRAR_MISSING_PASSWORD = 22,
  VNRAR_EREFERENCE = 23,
  VNRAR_BAD_PASSWORD = 24,
  VNRAR_LARGE_DICT = 25,
  // Shim specific
  VNRAR_ABORTED = 100,      // data callback asked to stop
  VNRAR_NEEDS_VOLUME = 101  // archive continues in another volume
};

// Archive flags (ROADF_*).
enum {
  VNRAR_ARC_VOLUME = 0x0001,
  VNRAR_ARC_COMMENT = 0x0002,
  VNRAR_ARC_LOCK = 0x0004,
  VNRAR_ARC_SOLID = 0x0008,
  VNRAR_ARC_NEWNUMBERING = 0x0010,
  VNRAR_ARC_SIGNED = 0x0020,
  VNRAR_ARC_RECOVERY = 0x0040,
  VNRAR_ARC_ENCHEADERS = 0x0080,
  VNRAR_ARC_FIRSTVOLUME = 0x0100
};

// Entry flags (RHDF_*).
enum {
  VNRAR_ENTRY_SPLITBEFORE = 0x01,
  VNRAR_ENTRY_SPLITAFTER = 0x02,
  VNRAR_ENTRY_ENCRYPTED = 0x04,
  VNRAR_ENTRY_SOLID = 0x10,
  VNRAR_ENTRY_DIRECTORY = 0x20
};

#define VNRAR_NAME_MAX 4096

typedef struct VNRarEntry {
  char name[VNRAR_NAME_MAX];   // UTF-8, '/' separated
  uint64_t packedSize;
  uint64_t unpackedSize;
  uint32_t flags;
  uint32_t method;             // 0x30 (store) ... 0x35
  uint32_t unpackVersion;      // 15/20/26/29/36 (RAR4) or 50/70 (RAR5)
  uint32_t dictSizeKB;
  uint32_t crc32;
  uint32_t redirType;          // non-zero: link/redirection entry
} VNRarEntry;

typedef struct VNRarArchive VNRarArchive;

// Called with decompressed data. Return 0 to continue, non-zero to abort.
typedef int (*vnrar_data_callback)(const unsigned char *data, size_t length, void *context);

// Opens an archive for extraction. On success *outArchive is set.
// archiveFlags receives VNRAR_ARC_* flags (may be NULL).
// listOnly != 0 opens in list mode: skipping entries never decompresses data,
// even for solid archives. Use extraction mode to read data.
int vnrar_open(const char *utf8Path, int listOnly, VNRarArchive **outArchive, uint32_t *archiveFlags);

// Reads the next entry header. Returns VNRAR_OK, VNRAR_END or an error.
int vnrar_next(VNRarArchive *archive, VNRarEntry *entry);

// Skips the data of the current entry (cheap for non-solid archives).
int vnrar_skip(VNRarArchive *archive);

// Decompresses (and verifies) the current entry, streaming data to callback.
int vnrar_read(VNRarArchive *archive, vnrar_data_callback callback, void *context);

void vnrar_close(VNRarArchive *archive);

// Version of the bundled unrar sources, e.g. 723 for 7.23.
int vnrar_unrar_version(void);

#ifdef __cplusplus
}
#endif

#endif
