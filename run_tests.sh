#!/bin/bash
set -e

if [ "$COVERALLS_TOKEN" ]; then
  # run tests on travis and publish code coverage
  pub global activate dart_coveralls
  pub global run dart_coveralls report \
    --token $COVERALLS_TOKEN \
    --retry 2 \
    --exclude-test-files \
    test/json_stream_parser_test.dart
else
  # run tests locally
  dart --checked test/json_stream_parser_test.dart
fi
