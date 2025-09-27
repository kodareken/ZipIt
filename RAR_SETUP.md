# RAR Compression Setup for ZipIt

## ✅ Current State: Clean-room RAR 4 Writer (Store-only)

ZipIt includes an internal, clean-room RAR 4.x writer for creating minimal RAR archives using the STORE method (no compression). No external RAR CLI is required.

- RAR Extraction: Fully supported via Unrar.swift
- RAR Compression: Experimental, RAR 4 container with METHOD=0x30 (STORE)
- Unicode names: ASCII-safe names only for MVP (no Unicode extra yet)
- Integrity: FILE_CRC32 and header CRC16 are written

### Quick Test (from the app)
1. Open ZipIt
2. Go to the "Compress" tab
3. Add a file or a folder
4. Choose "RAR"
5. Create the archive

### Optional Cross-Validation (if you have tools installed)
- 7-Zip or UnRAR CLI can be used to verify the archive:
  - 7z l / 7z x test.rar
  - unrar l / unrar x test.rar

> Note: These tools are not required for ZipIt to create basic RAR archives.

### Notes on Clean-room Implementation
- Implemented from public format descriptions (RAR Technote) and general compression literature
- No reverse engineering of proprietary code
- Currently STORE-only; future versions may add PPMd behind a feature flag

---

## 📁 Folder Compression

- ZIP: Recursive add, preserves structure
- TAR: Preserves hierarchies
- RAR: Recursive add with directory entries

### Known Limitations
- RAR write path is store-only (no compression)
- Unicode filenames beyond ASCII are not yet encoded in RAR4 Unicode extra field
- No solid archives, volumes, encryption, or comments in MVP
