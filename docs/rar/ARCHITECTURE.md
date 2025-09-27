# RAR Compression Architecture and Plan

This document captures our clean-room design to implement RAR 4.x compression in ZipIt for macOS.

Goals
- Emit valid, license-clean RAR 4.x archives that extract with standard tools (unrar/7z).
- Provide meaningful compression for text via PPMd first; later add LZ dictionary path for general binaries.
- Keep the implementation modular, testable, and safe for sandboxed macOS apps.

Scope of v1
- Container: RAR 4.x (aka RAR 3/4). RAR5 is out of scope initially.
- Methods: STORE (0x30) + PPMd (0x40..0x45 depending on mem model).
- Integrity: CRC32 for file data, CRC16 for header blocks.
- Optional (phase 2): x86 E8/E9 prefilter.

1) RAR 4 container (minimum viable layout)
- Signature: 52 61 72 21 1A 07 00 (7 bytes)
- Headers are LE and structured as:
  HEAD_CRC  (2)  // CRC-16 of header area (starting at HEAD_TYPE)
  HEAD_TYPE (1)  // 0x73 main, 0x74 file, 0x7B end of archive
  HEAD_FLAGS(2)
  HEAD_SIZE (2)  // size of this header (including these bytes, excluding payload)
  ... header fields depending on HEAD_TYPE ...

Main archive header (HEAD_TYPE=0x73)
- Fields (minimal):
  - HEAD_FLAGS: set SOLID bit if requested; otherwise 0.
  - Optional: Reserved fields as per spec (we’ll include canonical minimal fields).

File header (HEAD_TYPE=0x74)
- PACK_SIZE (4)  // compressed size
- UNP_SIZE  (4)  // uncompressed size
- HOST_OS   (1)  // 0x02 for Unix
- FILE_CRC  (4)  // CRC-32 of uncompressed data
- FTIME     (4)  // DOS time/date
- UNP_VER   (1)  // minimum unp version (e.g., 20)
- METHOD    (1)  // 0x30..0x35 (LZ) or 0x40..0x45 (PPMd)
- NAME_SIZE (2)  // file name length in bytes
- ATTR      (4)  // attributes; for Unix, permission bits
- NAME      (N)  // file name bytes
- DATA      (PACK_SIZE bytes)

End of archive header (HEAD_TYPE=0x7B)
- Minimal empty header (no payload) is acceptable.

Checksums
- FILE_CRC32: IEEE, reflected (poly 0xEDB88320), over original data.
- HEAD_CRC16: IBM CRC-16 over header bytes from HEAD_TYPE through end of header.

2) Compression methods to implement

A) STORE (0x30)
- No compression; just copy original bytes to DATA.
- Use as fallback or for already-compressed files.

B) PPMd (0x40..0x45)
- PPMd-J style order-N model (N≈4–6).
- Uses range coding (arithmetic coder) for symbol/escape coding.
- Memory (memMB) tunes model size; maps to method byte 0x40 + index.

PPMd encoder responsibilities
- Context tree with symbol frequency tables.
- Suffix links (lower-order fallback).
- Escape estimation (SEE) + rescaling.
- Update on every symbol; stream output via range coder.

Range coder responsibilities
- Maintain [low, high) interval; renormalize and flush bytes.
- Encode symbols per cumulative frequency tables.

C) Optional filters (phase 2)
- x86 E8/E9 transform to improve locality for code binaries. Reversible filter applied before PPMd/LZ.

3) Integration flow in ZipIt
- Strategy selection:
  - If text (heuristic), use PPMd(order=5, mem=16MB) -> METHOD 0x43 (example mapping), else STORE.
  - Later: LZ path for general binaries.

- Pipeline per file:
  1. Compute FILE_CRC32 over input.
  2. Optionally apply filter (future).
  3. Compress with selected encoder (PPMd or STORE) → payload, PACK_SIZE.
  4. Build File Header (HEAD_CRC16 over header area).
  5. Append payload.

4) API design (internal)
- RARContainerWriter
  - writeMainHeader(to:inout Data)
  - writeFileHeader(meta: RARFileMeta, to:inout Data)
  - writeEndHeader(to:inout Data)
- RARPPMdEncoder
  - init(order:Int, memMB:Int)
  - encode(input: UnsafeBufferPointer<UInt8>) -> Data
- RARCompressor
  - enum Method { case store, ppmd(order:Int, memMB:Int) }
  - func compress(_ data: Data, method: Method) -> (payload: Data, methodByte: UInt8)

5) Incremental milestones

Phase 0 – References + container correctness
- Add CRC16-IBM.
- Replace header writer to exact RAR4 layout (fixed LE fields, CRC16).
- Keep STORE path working end-to-end. Validate with `unrar x`.

Phase 1 – Range coder + PPMd minimal
- Implement range coder with tests.
- Implement order-4/5 PPMd with SEE; encode small text files.
- Integrate into RARCompressor; set METHOD byte accordingly.

Phase 2 – Heuristics & filters
- Text/binary detection; E8/E9 prefilter for x86 code.
- Choose STORE for already-compressed types.

Phase 3 – LZ path (optional)
- Hash-chain/binary-tree match finder; length/offset coding via range coder.

Phase 4 – Production polish
- Streaming I/O; large-file testing; perf tuning; Finder integration QA.

6) Test plan
- Unit tests for CRC16/32, DOS time conversion, LE packing.
- Golden-vector tests for range coder.
- Round-trip tests: create .rar → extract with `unrar`/`7z` → verify bytes & CRC.

7) Notes on legality and cleanliness
- Clean-room implementation based solely on public format descriptions and general compression literature. No proprietary code, no reverse engineering.
- Use permissive licensing for our own code; keep third-party dependencies separate and compliant.
