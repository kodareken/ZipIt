# 🗂️ ZipIt - Modern Archive Extractor for macOS

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2012+-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**ZipIt** is a modern, free, and open-source archive extractor for macOS built with SwiftUI. Created as a clean alternative to The Unarchiver, ZipIt provides native macOS integration without ads or bloatware.

<img width="300" height="300" alt="appicon" src="https://github.com/user-attachments/assets/2b26c4af-a037-425a-9656-96e3df78f0ce" />

## 🎯 The Problem

macOS handles ZIP files natively, but **doesn't support RAR files** out of the box. Users typically install The Unarchiver, but recent versions have introduced:
- 🚫 **Advertisement popups** 
- 🚫 **Bloated interface**
- 🚫 **Outdated user experience**

## ✨ The Solution

**ZipIt** is a lightweight, modern archive manager that:
- ✅ **100% Free & Open Source** - No ads, ever
- ✅ **Native macOS Integration** - Right-click → "Open With" support
- ✅ **Modern SwiftUI Interface** - Clean, intuitive design
- ✅ **RAR Support** - Extract RAR files (compression not supported - requires RARLAB license)
- ✅ **Quick Extract** - Cmd+Down Arrow for instant extraction
- ✅ **Create Archives** - ZIP and TAR compression. 7Z and GZ compression coming later.
- ✅ **Multiple Formats** - ZIP, RAR, 7Z, TAR, GZ (extraction for all; ZIP/TAR compression supported)

## 🚀 Features

### Archive Format Support
- **ZIP** - Full extraction and compression support
- **TAR** - Full extraction and compression support
- **RAR** - Extraction only (compression requires proprietary RARLAB license)
- **7Z** - Extraction support. Compression planned.
- **GZ/TGZ** - Extraction support. Compression planned.

### macOS Integration
- **File Association** - Set ZipIt as default for archive types
- **Quick Extract** - Select file → Cmd+Down Arrow → Instant extraction
- **Contextual Menu** - Right-click any archive → "Open With ZipIt"
- **Auto-destination** - Extracts to the same folder as the archive
- **Progress Tracking** - Real-time extraction progress

### User Experience
- **Modern UI** - Beautiful SwiftUI tabbed interface
- **Dual Mode** - Extract existing archives OR create new ones
- **Drag & Drop** - Simple file selection for both modes
- **Batch Selection** - Compress multiple files/folders at once
- **Error Handling** - Clear messages for password-protected or corrupted archives
- **Format Selection** - Choose output format when creating archives
- **Lightweight** - Minimal system resources
- **Fast** - Async operations with progress feedback

## 📥 Installation

### Option 1: Download Pre-built App (Recommended)
1. **Download** [`ZipIt.app`](ZipIt.app) from this repository
2. **Extract** the ZIP file (macOS handles this natively)
3. **Move** `ZipIt.app` to your `/Applications` folder
4. **Right-click** the app → "Open" (to bypass Gatekeeper on first run)

### Option 2: Build from Source
```bash
git clone https://github.com/kodareken/ZipIt.git
cd ZipIt
open ZipIt.xcodeproj
# Build and run in Xcode (Cmd+R)
```

## 🎯 Quick Start

### Basic Usage - Extraction
1. **Launch ZipIt** → **Extract Tab**
2. **Select Archive** - Choose your .rar, .zip, .7z, etc. file
3. **Choose Destination** - Pick where to extract (defaults to same folder)
4. **Extract** - Hit the extract button and watch the progress

### Basic Usage - Compression
1. **Launch ZipIt** → **Compress Tab** 
2. **Select Item** - Choose exactly one file or one folder (put multiple items in a folder first)
3. **Choose Format** - Pick ZIP or TAR
4. **Output Location** - ZipIt v1 always saves next to your selection
5. **Create Archive** - Hit the button and watch the progress

### Pro Usage: File Association
1. **Right-click** any RAR file in Finder
2. **"Get Info"** → "Open with" → Choose **ZipIt**
3. **"Change All..."** to set ZipIt as default for all RAR files
4. **Double-click** any RAR file → Opens directly in ZipIt

### Power User: Quick Extract
1. **Select** any archive file in Finder
2. **Press Cmd+Down Arrow** → Instantly extracts to same folder
3. **No UI needed** - Perfect for batch processing

## 🧪 Developer Testing

### Running Tests
- Run the whole test suite (unit + UI):
  ```bash
  xcodebuild test -project ZipIt.xcodeproj -scheme ZipIt -quiet
  ```

- Test RAR extraction with sample files:
  ```bash
  # RAR files can be extracted - try it with any sample RAR from the test suite
  unrar l "ZipItTests/Test files for supported formats/Samples .rar files/sample-1.rar"
  ```

## 🛠️ Technical Details

### Built With
- **Swift 5.9+** - Modern Swift language features
- **SwiftUI** - Native macOS interface framework
- **Unrar.swift** - RAR extraction library (extraction only)
- **SWCompression** - 7Z and TAR support (7Z compression planned; TAR compression supported)
- **Zip** - ZIP compression and extraction
- **Swift Package Manager** - Dependency management

### Architecture
- **MVVM Pattern** - Clean separation of concerns
- **Async/Await** - Non-blocking extraction
- **Combine** - Reactive progress tracking
- **Property Wrappers** - SwiftUI state management

### Supported Systems
- **macOS 12.0+** (Monterey and later)
- **Intel & Apple Silicon** - Universal binary support
- **Sandboxed** - App Store compatible

## 🤝 Contributing

We welcome contributions!

## 📝 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **[Unrar.swift](https://github.com/mtgto/Unrar.swift)** - RAR extraction capability
- **[SWCompression](https://github.com/tsolomko/SWCompression)** - 7Z and TAR support  
- **[Zip](https://github.com/marmelroy/Zip)** - Swift ZIP handling
- **[GzipSwift](https://github.com/1024jp/GzipSwift)** - Gzip compression
- **The frustrated macOS users** who needed a better alternative

---

### ⭐ If ZipIt helps you, please star this repository!

**Made with ❤️ for the macOS community by Kodareken (https://github.com/kodareken)

*Free software, no ads, no tracking, no BS. Just a tool that works.*
 
