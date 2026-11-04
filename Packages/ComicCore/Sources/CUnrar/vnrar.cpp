// VN Reader — C shim over unrar's dll.cpp API.
#include "rar.hpp"
#include "dll.hpp"
#include "version.hpp"
#include "../include/vnrar.h"

#include <new>

struct VNRarArchive {
  HANDLE handle = nullptr;
  vnrar_data_callback dataCallback = nullptr;
  void *dataContext = nullptr;
  bool aborted = false;
  bool needsVolume = false;
};

static int CALLBACK vnrar_unrar_callback(UINT msg, LPARAM userData, LPARAM p1, LPARAM p2) {
  VNRarArchive *a = reinterpret_cast<VNRarArchive *>(userData);
  switch (msg) {
    case UCM_PROCESSDATA:
      if (a != nullptr && a->dataCallback != nullptr) {
        if (a->dataCallback(reinterpret_cast<const unsigned char *>(p1), (size_t)p2, a->dataContext) != 0) {
          a->aborted = true;
          return -1;
        }
      }
      return 1;
    case UCM_NEEDPASSWORD:
    case UCM_NEEDPASSWORDW:
      // Encrypted archives are not supported: refuse to provide a password.
      return -1;
    case UCM_CHANGEVOLUME:
    case UCM_CHANGEVOLUMEW:
      if (p2 == RAR_VOL_ASK) {
        // Next volume is missing (multi-volume archives are not supported).
        if (a != nullptr) a->needsVolume = true;
        return -1;
      }
      return 1;
    case UCM_LARGEDICT:
      // Refuse dictionaries larger than the default limit (memory safety).
      return 0;
    default:
      return 0;
  }
}

extern "C" int vnrar_open(const char *utf8Path, int listOnly, VNRarArchive **outArchive, uint32_t *archiveFlags) {
  if (outArchive == nullptr || utf8Path == nullptr) return VNRAR_UNKNOWN;
  *outArchive = nullptr;
  VNRarArchive *a = new (std::nothrow) VNRarArchive();
  if (a == nullptr) return VNRAR_NO_MEMORY;

  std::wstring widePath;
  if (!UtfToWide(utf8Path, widePath)) {
    delete a;
    return VNRAR_EOPEN;
  }
  std::vector<wchar_t> pathBuf(widePath.begin(), widePath.end());
  pathBuf.push_back(0);

  RAROpenArchiveDataEx data;
  memset(&data, 0, sizeof(data));
  data.ArcNameW = pathBuf.data();
  data.OpenMode = listOnly ? RAR_OM_LIST_INCSPLIT : RAR_OM_EXTRACT;
  data.Callback = vnrar_unrar_callback;
  data.UserData = (LPARAM)a;

  HANDLE h = RAROpenArchiveEx(&data);
  if (h == nullptr || data.OpenResult != ERAR_SUCCESS) {
    if (a->needsVolume && data.OpenResult != ERAR_MISSING_PASSWORD) { if (h != nullptr) RARCloseArchive(h); delete a; return VNRAR_NEEDS_VOLUME; }
    int code = data.OpenResult != ERAR_SUCCESS ? (int)data.OpenResult : VNRAR_UNKNOWN;
    if (h != nullptr) RARCloseArchive(h);
    delete a;
    return code;
  }
  a->handle = h;
  if (archiveFlags != nullptr) *archiveFlags = data.Flags;
  *outArchive = a;
  return VNRAR_OK;
}

extern "C" int vnrar_next(VNRarArchive *a, VNRarEntry *entry) {
  if (a == nullptr || a->handle == nullptr || entry == nullptr) return VNRAR_UNKNOWN;
  RARHeaderDataEx *h = new (std::nothrow) RARHeaderDataEx;
  if (h == nullptr) return VNRAR_NO_MEMORY;
  memset(h, 0, sizeof(*h));
  std::vector<wchar_t> nameBuf(VNRAR_NAME_MAX, 0);
  h->FileNameEx = nameBuf.data();
  h->FileNameExSize = (unsigned int)nameBuf.size();

  a->needsVolume = false;
  int code = RARReadHeaderEx(a->handle, h);
  if (code != ERAR_SUCCESS) {
    delete h;
    if (a->needsVolume) return VNRAR_NEEDS_VOLUME;
    return code;
  }
  memset(entry, 0, sizeof(*entry));
  const wchar_t *wname = h->FileNameEx[0] != 0 ? h->FileNameEx : h->FileNameW;
  WideToUtf(wname, entry->name, sizeof(entry->name));
  // Normalise separators to '/'.
  for (char *c = entry->name; *c != 0; c++)
    if (*c == '\\') *c = '/';
  entry->packedSize = ((uint64_t)h->PackSizeHigh << 32) | h->PackSize;
  entry->unpackedSize = ((uint64_t)h->UnpSizeHigh << 32) | h->UnpSize;
  entry->flags = h->Flags;
  entry->method = h->Method;
  entry->unpackVersion = h->UnpVer;
  entry->dictSizeKB = h->DictSize;
  entry->crc32 = h->FileCRC;
  entry->redirType = h->RedirType;
  delete h;
  return VNRAR_OK;
}

extern "C" int vnrar_skip(VNRarArchive *a) {
  if (a == nullptr || a->handle == nullptr) return VNRAR_UNKNOWN;
  a->dataCallback = nullptr;
  a->dataContext = nullptr;
  a->needsVolume = false;
  int code = RARProcessFile(a->handle, RAR_SKIP, nullptr, nullptr);
  if (code != ERAR_SUCCESS && a->needsVolume) return VNRAR_NEEDS_VOLUME;
  return code;
}

extern "C" int vnrar_read(VNRarArchive *a, vnrar_data_callback callback, void *context) {
  if (a == nullptr || a->handle == nullptr) return VNRAR_UNKNOWN;
  a->dataCallback = callback;
  a->dataContext = context;
  a->aborted = false;
  a->needsVolume = false;
  int code = RARProcessFile(a->handle, RAR_TEST, nullptr, nullptr);
  a->dataCallback = nullptr;
  a->dataContext = nullptr;
  if (a->aborted) return VNRAR_ABORTED;
  if (code != ERAR_SUCCESS && a->needsVolume) return VNRAR_NEEDS_VOLUME;
  return code;
}

extern "C" void vnrar_close(VNRarArchive *a) {
  if (a == nullptr) return;
  if (a->handle != nullptr) RARCloseArchive(a->handle);
  delete a;
}

extern "C" int vnrar_unrar_version(void) {
  return RARVER_MAJOR * 100 + RARVER_MINOR;
}
