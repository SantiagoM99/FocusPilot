#!/bin/sh
# Builds a throwaway, unsandboxed, ad-hoc signed HerdrProbe.app next to this script.
set -eu
cd "$(dirname "$0")"
APP=build/HerdrProbe.app
rm -rf build && mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/HerdrProbe" main.swift
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"
