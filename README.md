# 🗂️ ZipIt - Modern Archive Extractor for macOS

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2012+-blue.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**ZipIt** is a modern, free, and open-source archive extractor for macOS built with SwiftUI. Created as a clean alternative to The Unarchiver, ZipIt provides native macOS integration without ads or bloatware.

![ZipIt App Screenshot](https://via.placeholder.com/800x500/4A90E2/FFFFFF?text=ZipIt+Archive+Extractor)

## 🎯 The Problem

macOS handles ZIP files natively, but **doesn't support RAR files** out of the box. Users typically install The Unarchiver, but recent versions have introduced:
- 🚫 **Advertisement popups** 
- 🚫 **Bloated interface**
- 🚫 **Outdated user experience**

> *"The Unarchiver has started showing ads and shit. So now in a modern era where AI can help you create your own Apps within minutes, we just created this app that people can use for free."* - [Reddit Discussion](https://www.reddit.com/r/MacOS/comments/1dug070/whats_a_good_unarchiver_alternative_do_i_even/)

## ✨ The Solution

**ZipIt** is a lightweight, modern archive manager that:
- ✅ **100% Free & Open Source** - No ads, ever
- ✅ **Native macOS Integration** - Right-click → "Open With" support
- ✅ **Modern SwiftUI Interface** - Clean, intuitive design
- ✅ **RAR Support** - Extract RAR files; Experimental write (RAR 4 store-only, no external tools)
- ✅ **Quick Extract** - Cmd+Down Arrow for instant extraction
- ✅ **Full Archive Management** - Extract AND create ZIP, 7Z, TAR, GZ archives
- ✅ **Multiple Formats** - ZIP, RAR, 7Z, TAR, GZ support

## 🚀 Features

### Archive Format Support
- **ZIP** - Full extraction and compression support
- **RAR** - Extraction only (compression is proprietary) 
- **7Z** - Full extraction and compression support
- **TAR** - Full extraction and compression support
- **GZ/TGZ** - Full extraction and compression support

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
1. **Download** [`ZipIt.zip`](ZipIt.zip) from this repository
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
2. **Select Files** - Choose multiple files and/or folders
3. **Choose Format** - Pick ZIP, 7Z, TAR, or GZ format
4. **Set Output** - Choose where to save the archive
5. **Create Archive** - Hit the compress button and watch the progress

### Pro Usage: File Association
1. **Right-click** any RAR file in Finder
2. **"Get Info"** → "Open with" → Choose **ZipIt**
3. **"Change All..."** to set ZipIt as default for all RAR files
4. **Double-click** any RAR file → Opens directly in ZipIt

### Power User: Quick Extract
1. **Select** any archive file in Finder
2. **Press Cmd+Down Arrow** → Instantly extracts to same folder
3. **No UI needed** - Perfect for batch processing

## 🛠️ Technical Details

### Built With
- **Swift 5.9+** - Modern Swift language features
- **SwiftUI** - Native macOS interface framework
- **Unrar.swift** - RAR extraction library
- **Internal RAR 4 writer (store-only, clean-room)**
- **SWCompression** - 7Z and TAR support
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

We welcome contributions! This app was built quickly with AI assistance, proving that modern development tools can solve real user problems in minutes.

### How to Contribute
1. **Fork** this repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Ideas for Contributions
- 🎨 **UI Improvements** - Better icons, animations, themes
- 🗜️ **New Formats** - Support for CAB, ISO, DMG, etc.
- ⚡ **Performance** - Faster extraction algorithms
- 🌐 **Localization** - Multi-language support
- 🔧 **Features** - Batch processing, password protection for compression

## 📝 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

## 🎉 Success Story

This entire application was conceptualized, designed, and built **in a single coding session** using:
- **Modern AI assistance** for rapid development
- **Swift Package Manager** for dependency management  
- **SwiftUI** for native macOS interface
- **Open source libraries** for archive format support

**Total development time: ~1 hours** ⏰

This proves that in 2025, individual developers can quickly create professional apps that solve real user problems, completely free from corporate bloatware and advertisements.

## 🙏 Acknowledgments

- **[Unrar.swift](https://github.com/mtgto/Unrar.swift)** - RAR extraction capability
- **[SWCompression](https://github.com/tsolomko/SWCompression)** - 7Z and TAR support  
- **[Zip](https://github.com/marmelroy/Zip)** - Swift ZIP handling
- **[GzipSwift](https://github.com/1024jp/GzipSwift)** - Gzip compression
- **The frustrated macOS users** who needed a better alternative

---

### ⭐ If ZipIt helps you, please star this repository!

**Made with ❤️ for the macOS community by Kodareken (https://github.com/kodareken) & Claude Sonnet**

*Free software, no ads, no tracking, no BS. Just a tool that works.*
 
