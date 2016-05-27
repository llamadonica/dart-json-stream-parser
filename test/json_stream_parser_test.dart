// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

library json_stream_parser.test;

import 'dart:async';
import 'dart:convert' as dart_convert;
import 'dart:typed_data';

import 'package:json_stream_parser/json_stream_parser.dart';
import 'package:test/test.dart';



void main() {
  group('json from utf8:', () {
    setUp(() {
    });
    var rawData = new dart_convert.Utf8Encoder().convert(TEST_STRING);

    test('utf8 decoder does not fail', () {
      var sink = new JsonListenerSink(new MyJsonListener());
      var decoder = new JsonUtf8Decoder().startChunkedConversion(sink);
      decoder.add(rawData);
      decoder.close();
    });
    test('our object is deep-equal to the dart:convert version', () {
      var ours = new JsonUtf8Decoder().convert(rawData);
      var theirs = new dart_convert.Utf8Decoder().fuse(new dart_convert.JsonDecoder()).convert(rawData);
      _deepEqual(ours, theirs);
    });
    test('decoder->encoder does not fail', () {
      var sink = new FuncSink<String>((data) {});
      var utf8Converter = new dart_convert.Utf8Decoder().startChunkedConversion(sink);
      var decoder = new JsonUtf8Decoder().startChunkedConversion(new JsonUtf8Encoder().startChunkedConversion(utf8Converter));
      decoder.add(rawData);
      decoder.close();
    });
    test('our encodig is the same as the dart:convert version', () {
      //We can relax this constraint later.
      var resultsB = [];
      var sink = new FuncSink<List<int>>((data) {
        resultsB.addAll(data);
      });
      var decoder = new JsonUtf8Decoder().startChunkedConversion(new JsonUtf8Encoder().startChunkedConversion(sink));
      var theirs = new dart_convert.JsonEncoder().fuse(new dart_convert.Utf8Encoder()).convert(new dart_convert.Utf8Decoder().fuse(new dart_convert.JsonDecoder()).convert(rawData));
      decoder.add(rawData);
      decoder.close();

      for (var i = 0; i < resultsB.length; i++) {
        expect(theirs[i], resultsB[i]);
      }
    });
    test('decoder speed test', () {
      var start = new DateTime.now();
      var i = 0;

      while (new DateTime.now().difference(start).inMilliseconds < 1000) {
        var sink = new FuncSink<List<JsonListenerEvent>>((data) {});
        var decoder = new JsonUtf8Decoder().startChunkedConversion(sink);
        decoder.add(rawData);
        decoder.close();
        i++;
      }
      print('We chunked $i times / sec (this doesn\'t reconstruct objects)');
      start = new DateTime.now();
      i = 0;

      while (new DateTime.now().difference(start).inMilliseconds < 1000) {
        var decoder = new dart_convert.Utf8Decoder().fuse(new dart_convert.JsonDecoder()).convert(rawData);
        i++;
      }
      print('Native dart convert $i times / sec');
    });
    test('decoder speed test', () {
      var start = new DateTime.now();
      var i = 0;

      while (new DateTime.now().difference(start).inMilliseconds < 1000) {
        var decoder = new JsonUtf8Decoder().convert(rawData);
        i++;
      }
      print('We chunked $i times / sec (this completely reconstructs objects)');
      start = new DateTime.now();
      i = 0;

      while (new DateTime.now().difference(start).inMilliseconds < 1000) {
        var decoder = new dart_convert.Utf8Decoder().fuse(new dart_convert.JsonDecoder()).convert(rawData);
        i++;
      }
      print('Native dart convert $i times / sec');
    });
    test('reencoding always produces the same results', () {
      var sink = new FuncSink<String>((data) {
        print(data);
      });
      var utf8Converter = new dart_convert.Utf8Decoder().startChunkedConversion(sink);

      var resultsB = [];
      var sinkB = new FuncSink<List<int>>((data) {
        utf8Converter.add(data);
        resultsB.addAll(data);
      });
      var decoderB = new JsonUtf8Decoder().startChunkedConversion(new JsonUtf8Encoder().startChunkedConversion(sinkB));

      var resultsA = [];
      var sinkA = new FuncSink<List<int>>((data) {
        resultsA.addAll(data);
        decoderB.add(data);
      }, onClose: () {
        decoderB.close();
      });
      var decoderA = new JsonUtf8Decoder().startChunkedConversion(new JsonUtf8Encoder().startChunkedConversion(sinkA));
      decoderA.add(rawData);
      decoderA.close();
      utf8Converter.close();

      for (var i = 0; i < resultsA.length; i++) {
        expect(resultsA[i], resultsB[i]);
      }
    });
    test('an BuildJsonListener also produces the same result as dart:convert', () {
      var builder = new BuildJsonListener();
      var sinkB = new JsonListenerSink(builder);
      var decoderB = new JsonUtf8Decoder().startChunkedConversion(sinkB);
      decoderB.add(rawData);
      decoderB.close();

      var theirs = new dart_convert.Utf8Decoder().fuse(new dart_convert.JsonDecoder()).convert(rawData);

      _deepEqual(builder.result, theirs);
    });
    test('splitting into tiny chunks has no effect', () {
      var resultsB = [];
      var sinkB = new FuncSink<List<int>>((data) {
        resultsB.addAll(data);
      });
      var decoderB = new JsonUtf8Decoder().startChunkedConversion(new JsonUtf8Encoder().startChunkedConversion(sinkB));

      var resultsA = [];
      var sinkA = new FuncSink<List<int>>((data) {
        resultsA.addAll(data);
        for (var byte in data) {
          decoderB.add([byte]);
        }
      }, onClose: () => decoderB.close());
      var decoderA = new JsonUtf8Decoder().startChunkedConversion(new JsonUtf8Encoder().startChunkedConversion(sinkA));
      decoderA.add(rawData);
      decoderA.close();

      for (var i = 0; i < resultsA.length; i++) {
        expect(resultsA[i], resultsB[i]);
      }
    });
  });
  group('json from strings:', () {
    setUp(() {
    });
    var rawData = TEST_STRING;

    test('utf8 decoder does not fail', () {
      var sink = new JsonListenerSink(new MyJsonListener());
      var decoder = new JsonDecoder().startChunkedConversion(sink);
      decoder.add(rawData);
      decoder.close();
    });
    test('our object is deep-equal to the dart:convert version', () {
      var ours = new JsonDecoder().convert(rawData);
      var theirs = new dart_convert.JsonDecoder().convert(rawData);
      _deepEqual(ours, theirs);
    });
    test('decoder->encoder does not fail', () {
      var sink = new FuncSink<String>((data) {});
      var decoder = new JsonDecoder().startChunkedConversion(new JsonEncoder().startChunkedConversion(sink));
      decoder.add(rawData);
      decoder.close();
    });
    test('our encodig is the same as the dart:convert version', () {
      //We can relax this constraint later.
      var resultsB = new StringBuffer();
      var sink = new FuncSink<String>((data) {
        resultsB.write(data);
      });
      var decoder = new JsonDecoder().startChunkedConversion(new JsonEncoder().startChunkedConversion(sink));
      var theirs = new dart_convert.JsonEncoder().convert(new dart_convert.JsonDecoder().convert(rawData));
      decoder.add(rawData);
      decoder.close();

      expect(theirs, resultsB.toString());
    });
    test('decoder speed test', () {
      var start = new DateTime.now();
      var i = 0;

      while (new DateTime.now().difference(start).inMilliseconds < 1000) {
        var sink = new FuncSink((data) {});
        var decoder = new JsonDecoder().startChunkedConversion(sink);
        decoder.add(rawData);
        decoder.close();
        i++;
      }
      print('We chunked $i times / sec (this doesn\'t reconstruct objects)');
      start = new DateTime.now();
      i = 0;

      while (new DateTime.now().difference(start).inMilliseconds < 1000) {
        var decoder = new dart_convert.JsonDecoder().convert(rawData);
        i++;
      }
      print('Native dart convert $i times / sec');
    });
    test('decoder speed test', () {
      var start = new DateTime.now();
      var i = 0;

      while (new DateTime.now().difference(start).inMilliseconds < 1000) {
        var decoder = new JsonDecoder().convert(rawData);
        i++;
      }
      print('We chunked $i times / sec (this completely reconstructs objects)');
      start = new DateTime.now();
      i = 0;

      while (new DateTime.now().difference(start).inMilliseconds < 1000) {
        var decoder = new dart_convert.JsonDecoder().convert(rawData);
        i++;
      }
      print('Native dart convert $i times / sec');
    });
    test('reencoding always produces the same results', () {
      var sink = new FuncSink<String>((data) {
      });

      var resultsB = new StringBuffer();
      var sinkB = new FuncSink<String>((data) {
        sink.add(data);
        resultsB.write(data);
      });
      var decoderB = new JsonDecoder().startChunkedConversion(new JsonEncoder().startChunkedConversion(sinkB));

      var resultsA = new StringBuffer();
      var sinkA = new FuncSink<String>((data) {
        resultsA.write(data);
        decoderB.add(data);
      }, onClose: () {
        decoderB.close();
      });
      var decoderA = new JsonDecoder().startChunkedConversion(new JsonEncoder().startChunkedConversion(sinkA));
      decoderA.add(rawData);
      decoderA.close();

      expect(resultsA.toString(), resultsB.toString());
    });
    test('an BuildJsonListener also produces the same result as dart:convert', () {
      var builder = new BuildJsonListener();
      var sinkB = new JsonListenerSink(builder);
      var decoderB = new JsonDecoder().startChunkedConversion(sinkB);
      decoderB.add(rawData);
      decoderB.close();

      var theirs = new dart_convert.JsonDecoder().convert(rawData);

      _deepEqual(builder.result, theirs);
    });
    test('splitting into tiny chunks has no effect', () {
      var resultsB = new StringBuffer();
      var sinkB = new FuncSink<String>((data) {
        resultsB.write(data);
      });
      var decoderB = new JsonDecoder().startChunkedConversion(new JsonEncoder().startChunkedConversion(sinkB));

      var resultsA = new StringBuffer();
      var sinkA = new FuncSink<String>((String data) {
        resultsA.write(data);
        for (var byte in data.codeUnits) {
          decoderB.add(new String.fromCharCode(byte));
        }
      });
      var decoderA = new JsonDecoder().startChunkedConversion(new JsonEncoder().startChunkedConversion(sinkA));
      decoderA.add(rawData);
      decoderA.close();

      expect(resultsA.toString(), resultsB.toString());
    });
  });
}

void _deepEqual(Object ours, Object theirs) {
  if (theirs is Map) {
    expect(ours is Map, true);
    for (var key in ours.keys) {
      expect(theirs.containsKey(key), true);
      _deepEqual(ours[key], theirs[key]);
    }
    for (var key in theirs.keys) {
      expect(ours.containsKey(key), true);
    }
  } else if (theirs is List) {
    expect(ours is List, true);
    expect(ours.length, theirs.length);
    for (var i = 0; i < theirs.length; i++) {
      _deepEqual(ours[i], theirs[i]);
    }
  } else {
    expect(ours, theirs);
  }
}

Uint8List slowCopy(Uint8List originalBuffer, int i, int j) =>
  new Uint8List(j - i)
    ..setRange(0, j - i, originalBuffer, i);


class MyJsonListener extends JsonListener {

  @override
  void arrayElement() {
  }

  @override
  void beginArray() {
  }

  @override
  void beginObject() {
  }

  @override
  void endArray() {
  }

  @override
  void endObject() {
  }

  @override
  void handleBool(bool value) {
  }

  @override
  void handleNull() {
  }

  @override
  void handleNumber(num value) {
  }

  @override
  void handleString(String value) {
  }

  @override
  void propertyName() {
  }

  @override
  void propertyValue() {
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
      [{
        "id": 0,
        "name": "Deborah Hyde"
      }],
      [{
        "id": 1,
        "name": "Morris Rutledge"
      }],
      [{
        "id": 2,
        "name": "Cristina Reed"
      }]
    ],
    "greeting": "Hello, Pollard Robinson! You have 8 unread messages.",
    "favoriteFruit": "strawberry"
  }
''';
