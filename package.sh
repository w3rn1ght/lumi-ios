#!/bin/sh
# This script sets executable permissions and builds the .deb package

chmod +x layout/DEBIAN/postinst layout/DEBIAN/postrm
echo "=== Executable permissions set ==="
echo "=== Starting build ==="
make package

echo "=== Build complete ==="