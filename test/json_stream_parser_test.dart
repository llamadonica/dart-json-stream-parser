// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library json_stream_parser.test;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:json_stream_parser/json_stream_parser.dart';
import 'package:test/test.dart';



void main() {
  group('Fast buffer copies', () {
    setUp(() {

    });
    test('provide the same results as slower but safer copies', () {
      var originalBuffer = new Uint8List(64*1024);
      for (var i = 0; i < 64*1024; i++) {
        originalBuffer[i] = i & 0xFF;
      }
      var bufferCopyA = fastCopy(originalBuffer, 0, 64*1024);
      var bufferCopyB = slowCopy(originalBuffer, 0, 64*1024);
      for (var i = 0; i < 64*1024; i++) {
        expect(bufferCopyA[i], bufferCopyB[i]);
      }
    });
    test('Provide the same results as slower but safer copies', () {
      var originalBuffer = new Uint8List(64*1024 + 6);
      for (var i = 0; i < 64*1024 + 6; i++) {
        originalBuffer[i] = i & 0xFF;
      }
      var bufferCopyA = fastCopy(originalBuffer, 0, 64*1024 + 6);
      var bufferCopyB = slowCopy(originalBuffer, 0, 64*1024 + 6);
      for (var i = 0; i < 64*1024 + 6; i++) {
        expect(bufferCopyA[i], bufferCopyB[i]);
      }
    });
    test('Provide the same results as slower but safer copies', () {
      var originalBuffer = new Uint8List(64*1024 + 6);
      for (var i = 0; i < 64*1024 + 6; i++) {
        originalBuffer[i] = i & 0xFF;
      }
      var bufferCopyA = fastCopy(originalBuffer, 6, 64*1024 + 6);
      var bufferCopyB = slowCopy(originalBuffer, 6, 64*1024 + 6);
      for (var i = 0; i < 64*1024; i++) {
        expect(bufferCopyA[i], bufferCopyB[i]);
      }
    });
    test('Provide the same results as slower but safer copies', () {
      var originalBuffer = new Uint8List(64*1024 + 6);
      for (var i = 0; i < 64*1024 + 6; i++) {
        originalBuffer[i] = i & 0xFF;
      }
      var modifiedBuffer = new Uint8List.view(originalBuffer.buffer, 6, 64*1024);
      var bufferCopyA = fastCopy(modifiedBuffer, 0, 64*1024);
      var bufferCopyB = slowCopy(modifiedBuffer, 0, 64*1024);
      for (var i = 0; i < 64*1024; i++) {
        expect(bufferCopyA[i], bufferCopyB[i]);
      }
    });
  });
  group('Json fast parser', () {
    setUp(() {
    });
    var rawData = new Utf8Encoder().convert(TEST_STRING);
    test('decoder does not fail', () {
      var sink = new FuncSink<JsonStreamingEventFast>((data) {
      });
      var decoder = new JsonUtf8DecodeSinkFast(sink);
      decoder.add(rawData);
      decoder.close();
    });
    test('decoder does not fail', () {
      var sink = new FuncSink<List<int>>((data) {
      });
      var decoder = new JsonUtf8DecodeSinkFast(new JsonUtf8EncodeSinkFast(sink));
      decoder.add(rawData);
      decoder.close();
    });
    test('decoder speed test', () {
      var start = new DateTime.now();
      var i = 0;

      while (new DateTime.now().difference(start).inMilliseconds < 1000) {
        var sink = new FuncSink<List<int>>((data) {});
        var decoder = new JsonUtf8DecodeSinkFast(
            new JsonUtf8EncodeSinkFast(sink));
        decoder.add(rawData);
        decoder.close();
        i++;
      }
      print('We chunked $i times / sec');
    });
    test('reencoding always produces the same results', () {
      var resultsB = [];
      var sinkB = new FuncSink<List<int>>((data) {
        resultsB.addAll(data);
      });
      var decoderB = new JsonUtf8DecodeSinkFast(new JsonUtf8EncodeSinkFast(sinkB));

      var resultsA = [];
      var sinkA = new FuncSink<List<int>>((data) {
        resultsA.addAll(data);
        decoderB.add(data);
      });
      var decoderA = new JsonUtf8DecodeSinkFast(new JsonUtf8EncodeSinkFast(sinkA));
      decoderA.add(rawData);
      decoderA.close();

      for (var i = 0; i < resultsA.length; i++) {
        expect(resultsA[i], resultsB[i]);
      }
    });
    test('splitting into tiny chunks has no effect', () {
      var resultsB = [];
      var sinkB = new FuncSink<List<int>>((data) {
        resultsB.addAll(data);
      });
      var decoderB = new JsonUtf8DecodeSinkFast(new JsonUtf8EncodeSinkFast(sinkB));

      var resultsA = [];
      var sinkA = new FuncSink<List<int>>((data) {
        resultsA.addAll(data);
        for (var byte in data) {
          decoderB.add([byte]);
        }
      });
      var decoderA = new JsonUtf8DecodeSinkFast(new JsonUtf8EncodeSinkFast(sinkA));
      decoderA.add(rawData);
      decoderA.close();

      for (var i = 0; i < resultsA.length; i++) {
        expect(resultsA[i], resultsB[i]);
      }
    });
    test('Path-setter emitter', () {
      var sink = new FuncSink<PathSetterEvent>((data) {
      });
      var decoder = new JsonUtf8DecodeSinkFast(new PathSetterDecoderSink(sink));
      decoder.add(rawData);
      decoder.close();
    });
    test('Path-setter emitter speed test', () {
      var start = new DateTime.now();
      var i = 0;

      while (new DateTime.now().difference(start).inMilliseconds < 1000) {
        var sink = new FuncSink<PathSetterEvent>((data) {});
        var decoder = new JsonUtf8DecodeSinkFast(
            new PathSetterDecoderSink(sink));
        decoder.add(rawData);
        decoder.close();
        i++;
      }
      print("We converted $i times / sec");
    });

    test('Path reviver', () async {
      var sink = new PathReviver();
      var decoder = new JsonUtf8DecodeSinkFast(new PathSetterDecoderSink(sink));
      decoder.add(rawData);
      decoder.close();
      var result = await sink;
    });

    test('Path reviver speed test', () async {
      var start = new DateTime.now();
      var i = 0;

      while (new DateTime.now().difference(start).inMilliseconds < 1000) {
        var sink = new PathReviver();
        var decoder = new JsonUtf8DecodeSinkFast(
            new PathSetterDecoderSink(sink))
          ..add(rawData)
          ..close();
        var result = await sink;
        i++;
      }
      print("We converted $i times / sec");

      i = 0;
      start = new DateTime.now();
      while (new DateTime.now().difference(start).inMilliseconds < 1000) {
        var result = new Utf8Encoder().convert(new JsonEncoder().convert(new JsonDecoder().convert(new Utf8Decoder().convert(rawData))));
        i++;
      }
      print("dart:convert can go $i times / sec");
    });
  });
}

Uint8List slowCopy(Uint8List originalBuffer, int i, int j) =>
  new Uint8List(j - i)
    ..setRange(0, j - i, originalBuffer, i);

class PrintSink extends Sink<JsonStreamingEventFast> {
  @override
  void add(data) {
    stdout.write('\nSYMBOL: ');
    stdout.add(data.bytestream);
  }

  @override
  void close() {
  }
}

typedef void AddFunc<T>(T data);
typedef void CloseFunc();

class FuncSink<T> extends Sink<T> {
  final AddFunc<T> _add;
  final CloseFunc _close;

  FuncSink(this._add, {CloseFunc onClose : _defaultClose}) : _close = onClose;

  static void _defaultClose() {}

  @override
  void add(T data) => _add(data);

  @override
  void close() => _close();
}

const TEST_STRING = r'''{
    "_id": "56088d4fd91cc0b3a010bfde",
    "index": 0,
    "guid": "f7b9afd6-77ce-49ad-9d36-96a4502773dc",
    "isActive": true,
    "balance": "$1,811.87",
    "picture": "http://placehold.it/32x32",
    "age": 28,
    "eyeColor": "blue",
    "name": "Pollard Robinson",
    "gender": "male",
    "company": "ZOSIS",
    "email": "pollardrobinson@zosis.com",
    "phone": "+1 (923) 491-2189",
    "address": "860 Varanda Place, Lawrence, New York, 9963",
    "about": "Dolore nostrud amet occaecat minim occaecat\nlabore anim excepteur aliquip\u25e2\"tempor aliqua magna. Eu cupidatat aliqua officia do sunt. Voluptate dolore veniam cillum minim ex elit exercitation tempor laboris magna.\r\n",
    "registered": "2014-05-23T11:31:33 +07:00",
    "latitude": -35.311561,
    "longitude": 142.474102,
    "tags": [
      "id",
      "consectetur",
      "Lorem",
      "exercitation",
      "aliquip",
      "incididunt",
      "reprehenderit"
    ],
    "friends": [
      {
        "id": 0,
        "name": "Deborah Hyde"
      },
      {
        "id": 1,
        "name": "Morris Rutledge"
      },
      {
        "id": 2,
        "name": "Cristina Reed"
      }
    ],
    "greeting": "Hello, Pollard Robinson! You have 8 unread messages.",
    "favoriteFruit": "strawberry"
  }
''';
