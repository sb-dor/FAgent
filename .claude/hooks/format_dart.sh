#!/bin/bash
# PostToolUse: format the .dart file Claude just edited. Generated files are skipped.
f=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty')
case "$f" in
  *.g.dart | *.freezed.dart | */generated/*) exit 0 ;;
  *.dart) dart format "$f" >/dev/null ;;
esac
