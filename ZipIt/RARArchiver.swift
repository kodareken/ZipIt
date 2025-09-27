//
//  RARArchiver.swift
//  ZipIt
//
//  CLEAN-ROOM IMPLEMENTATION NOTICE:
//  This file implements RAR archive format writing based on publicly available
//  specifications from rarlab.com/technote.htm. No reverse engineering performed.
//

import Foundation

/// RAR archive writer implementing the publicly documented format (RAR 4.x container)
public class RARArchiver {
    
    // RAR 4.x signature
    private static let RAR_SIGNATURE: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]
    
    // Header constants (RAR 4)
    private static let HEAD_TYPE_MAIN: UInt8 = 0x73
    private static let HEAD_TYPE_FILE: UInt8 = 0x74
    private static let HEAD_TYPE_END:  UInt8 = 0x7B
    private static let HFLG_LONG_BLOCK: UInt16 = 0x8000
    
    // Compression methods (RAR 4)
    private static let COMP_METHOD_STORE: UInt8 = 0x30    // '0' - No compression
    // PPMd methods start at 0x40 in RAR4; LZ levels 0x31..0x35 not used yet here
    
    // Host OS types (RAR 4)
    private static let HOST_OS_MSDOS: UInt8 = 0x00
    private static let HOST_OS_UNIX:  UInt8 = 0x02
    
    private let compressor = RARCompressor()
    private var entries: [RAREntry] = []
    private var archiveFlags: UInt16 = 0
    
    public init(solid: Bool = false, recoveryRecord: Bool = false) {
        self.archiveFlags = 0
        if solid { /* RAR4 solid flag is in main header flags; keep 0 for MVP */ }
        if recoveryRecord { /* Recovery record not implemented; keep 0 */ }
    }
    
    /// Add file entry to archive
    public func addFile(name: String, data: Data, comment: String? = nil) throws {
        let entry = RAREntry(
            name: name,
            data: data,
            isDirectory: false,
            compressedSize: 0,
            uncompressedSize: UInt32(data.count),
            compressionMethod: RARArchiver.COMP_METHOD_STORE,
            crc32: data.crc32,
            comment: comment,
            fileTime: nil
        )
        entries.append(entry)
    }
    
    /// Add directory entry to archive
    public func addDirectory(name: String, comment: String? = nil) throws {
        let entry = RAREntry(
            name: name + "/",  // Directories always end with "/"
            data: Data(),
            isDirectory: true,
            compressedSize: 0,
            uncompressedSize: 0,
            compressionMethod: RARArchiver.COMP_METHOD_STORE,
            crc32: 0,
            comment: comment,
            fileTime: nil
        )
        entries.append(entry)
    }
    
    /// Create complete RAR archive (RAR 4.x)
    public func createArchive() throws -> Data {
        var archive = Data()
        
        // Signature
        archive.append(contentsOf: RARArchiver.RAR_SIGNATURE)
        
        // Main header
        writeMainHeader(into: &archive)
        
        // Files
        for e in entries {
            // Determine packed payload (STORE for now)
            let payload: Data
            if e.isDirectory {
                payload = Data()
            } else if e.compressionMethod == RARArchiver.COMP_METHOD_STORE {
                payload = e.data
            } else {
                payload = try compressor.compressData(e.data)
            }
            writeFileHeader(entry: e, packedSize: UInt32(payload.count), into: &archive)
            archive.append(payload)
        }
        
        // End header
        writeEndHeader(into: &archive)
        return archive
    }
    
    // MARK: - RAR4 header writers
    
    private func writeMainHeader(into out: inout Data) {
        // Build header (excluding HEAD_CRC)
        var hdr = Data()
        hdr.append(RARArchiver.HEAD_TYPE_MAIN)
        appendLE(UInt16(0x0000), to: &hdr) // HEAD_FLAGS
        // No body fields for minimal main header
        let headSize = UInt16(7)
        appendLE(headSize, to: &hdr)
        // Compute CRC16 over TYPE..end (RAR4 header CRC uses CRC-16/IBM with init 0xFFFF)
        let crc = crc16Header(hdr)
        var rec = Data()
        appendLE(crc, to: &rec)
        rec.append(hdr)
        out.append(rec)
    }
    
    private func writeFileHeader(entry: RAREntry, packedSize: UInt32, into out: inout Data) {
        // Build body fields (FILE_HEAD data)
        var body = Data()
        appendLE(packedSize, to: &body)                 // PACK_SIZE
        appendLE(entry.uncompressedSize, to: &body)     // UNP_SIZE
        body.append(RARArchiver.HOST_OS_UNIX)           // HOST_OS
        appendLE(entry.crc32, to: &body)                // FILE_CRC (CRC32 of uncompressed data)
        let dosTime = entry.fileTime ?? DOSTime.from(Date())
        appendLE(dosTime, to: &body)                    // FTIME (DOS)
        body.append(0x29)                                // UNP_VER (2.9 for broad compatibility)
        body.append(entry.compressionMethod)            // METHOD (0x30 = STORE)
        let nameData = entry.name.data(using: .utf8) ?? Data()
        appendLE(UInt16(nameData.count), to: &body)     // NAME_SIZE (bytes)
        // ATTR: Use POSIX-like mode bits (S_IFREG/S_IFDIR + perms) for UNIX host
        let attr: UInt32 = entry.isDirectory ? (0x4000 | 0o755) : (0x8000 | 0o644)
        appendLE(attr, to: &body)                       // ATTR
        body.append(nameData)                           // NAME

        // Build header prefix (TYPE, FLAGS, SIZE). HEAD_SIZE excludes ADD_SIZE
        var headerPrefix = Data()
        headerPrefix.append(RARArchiver.HEAD_TYPE_FILE)
        let flags: UInt16 = RARArchiver.HFLG_LONG_BLOCK // indicate ADD_SIZE present (payload)
        appendLE(flags, to: &headerPrefix)
        let headSize = UInt16(5 + body.count) // TYPE(1)+FLAGS(2)+SIZE(2)+body
        appendLE(headSize, to: &headerPrefix)

        // Header CRC16 is over [TYPE,FLAGS,SIZE,body] with init 0xFFFF
        var headerCore = Data()
        headerCore.append(headerPrefix)
        headerCore.append(body)
        let crc = crc16Header(headerCore)

        // Assemble final record: [HEAD_CRC16][TYPE,FLAGS,SIZE][ADD_SIZE][BODY]
        var rec = Data()
        appendLE(crc, to: &rec)
        rec.append(headerPrefix)
        appendLE(packedSize, to: &rec) // ADD_SIZE = payload size (present because LONG_BLOCK)
        rec.append(body)
        out.append(rec)
    }
    /// Write file data block
    private func writeFileData(_ entry: RAREntry, to archive: inout Data) throws {
        if entry.isDirectory {
            return
        }
        if entry.compressionMethod == RARArchiver.COMP_METHOD_STORE {
            archive.append(entry.data)
        } else {
            let compressedData = try compressor.compressData(entry.data)
            archive.append(compressedData)
        }
    }
    
    private func writeEndHeader(into out: inout Data) {
        var hdr = Data()
        hdr.append(RARArchiver.HEAD_TYPE_END)
        appendLE(UInt16(0x0000), to: &hdr)
        let headSize = UInt16(7) // TYPE+FLAGS+SIZE only
        appendLE(headSize, to: &hdr)
        let crc = crc16Header(hdr)
        var rec = Data()
        appendLE(crc, to: &rec)
        rec.append(hdr)
        out.append(rec)
    }
    
    // MARK: - Helpers
    private func appendLE(_ v: UInt16, to data: inout Data) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
    private func appendLE(_ v: UInt32, to data: inout Data) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
    private func crc16Header(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in data { crc ^= UInt16(b); for _ in 0..<8 { let lsb = crc & 1; crc >>= 1; if lsb != 0 { crc ^= 0xA001 } } }
        return crc
    }
}

/// Structure representing a RAR archive entry
struct RAREntry {
    let name: String
    let data: Data
    let isDirectory: Bool
    var compressedSize: UInt32
    var uncompressedSize: UInt32
    let compressionMethod: UInt8
    let crc32: UInt32
    let comment: String?
    let fileTime: UInt32?
}