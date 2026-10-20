#!/bin/sh
# Tests the Chrome extension's pure logic (policy, outbox, blocked page) with
# node's built-in test runner; no packages are installed.
set -eu
cd "$(dirname "$0")/.."
node --test Tests/ChromeExtension/
