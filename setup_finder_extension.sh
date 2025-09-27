# ZipIt Finder Extension Setup
# Run this script after adding a new Finder Extension target in Xcode

# 1. In Xcode, add a new target:
# File > New > Target > Finder Extension
# Name: ZipItFinderExtension
# 
# 2. Replace the generated FinderSync.swift with our implementation:
# Copy /Users/admin/Code/4.github_repos/ZipIt/ZipItFinderExtension/FinderSync.swift 
# to the Finder Extension target
#
# 3. Update the Info.plist:
# Copy /Users/admin/Code/4.github_repos/ZipIt/ZipItFinderExtension/Info.plist
# to the Finder Extension target
#
# 4. Configure the Finder extension target:
# - Set Product Bundle Identifier: com.ZipIt.ZipItFinderExtension
# - Set Principal Class: FinderSync
# - Set Application Group: com.ZipIt (if using app groups)
#
# 5. Add entitlements to main app (ZipIt.entitlements):
cat >> ZipIt/ZipIt.entitlements << EOF
    <key>com.apple.security.scripting-targets</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>com.ZipIt</string>
    </array>
EOF

# 6. Add to Finder extension entitlements:
cat >> ZipItFinderExtension/*.entitlements << EOF
    <key>com.apple.security.application-groups</key>
    <array>
        <string>com.ZipIt</string>
    </array>
    <key>com.apple.security.temporary-exception.shared-preference.read-write</key>
    <array>
        <string>com.ZipIt</string>
    </array>
EOF

echo "Finder Extension setup complete!"