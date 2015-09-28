# json_stream_parser

[![Build Status](https://travis-ci.org/llamadonica/dart-json-stream-parser.svg)](https://travis-ci.org/llamadonica/dart-json-stream-parser)
[![Coverage Status](https://coveralls.io/repos/llamadonica/dart-json-stream-parser/badge.svg?branch=master&service=github)](https://coveralls.io/github/llamadonica/dart-json-stream-parser?branch=master)

A library for processing streams of json. Unlike the built-in parser, it can process JSON as
tokens are processed, giving better intermediate results, especially for long-running queries or
large files.

It can be used both on server- and client-side.

## Usage

A simple usage example:

    import 'package:json_stream_parser/json_stream_parser.dart';

    main() {
      final file = new File('file.json');
      Stream<List<int>> inputStream =
        file.openRead()
        .expand((t) => t)
        .transform(jsonStreamingTransformation);
    }

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/llamadonica/dart-json-stream-parser/issues
