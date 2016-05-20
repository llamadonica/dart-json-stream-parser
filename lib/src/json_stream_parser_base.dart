// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

// TODO: Put public facing types in this file.

library json_stream_parser.base;

import 'dart:async';
import 'dart:convert';

enum JsonStreamingBox { array, object, na }
enum JsonStreamingEventType { open, close, token }

enum _SubParser {
  begin,
  top,
  string,
  numberPart1,
  numberPart2,
  numberPart3,
  numberPart4,
  end,
  rawToken,
  errored
}



class JsonStreamingEvent {
  final JsonStreamingBox boxType;
  final JsonStreamingEventType eventType;
  final List path;
  final symbol;

  JsonStreamingEvent(JsonStreamingBox this.boxType, Iterable _path,
      dynamic this.symbol, JsonStreamingEventType this.eventType)
      : path = new List.from(_path);

  String toString() {
    var output = new StringBuffer('JsonStreamingEvent(');
    output.write(boxType);
    output.write(',');
    output.write(path);
    output.write(',');
    output.write(symbol);
    output.write(')');
    return output.toString();
  }
}

StreamTransformer<int, JsonStreamingEvent> get jsonStreamingTransformation =>
    const JsonStreamTransformer();

class JsonUtf8StreamCodec extends Codec<Object, List<int>> {
  final bool isImplicitArray;

  const JsonUtf8StreamCodec([this.isImplicitArray = false]);

  @override
  JsonUtf8StreamDecoder get decoder => new JsonUtf8StreamDecoder(this.isImplicitArray);

  // TODO: implement encoder
  @override
  ChunkedConverter<dynamic, List<int>, JsonStreamingEvent, List<int>>
      get encoder => new JsonUtf8StreamEncoder(this.isImplicitArray);
}

class JsonUtf8StreamEncoder extends ChunkedConverter<dynamic, List<int>,
    JsonStreamingEvent, List<int>> {
  final bool isImplicitArray;

  const JsonUtf8StreamEncoder(this.isImplicitArray);

  @override
  List<int> convert(dynamic input) {
    //TODO: Convert this.
  }

  @override
  ChunkedConversionSink<JsonStreamingEvent> startChunkedConversion(
          Sink<List<int>> sink) =>
      new _JsonUtf8EncodeSink(sink, isImplicitArray);
}

typedef void StreamDumper(JsonStreamingEvent event);

class _JsonUtf8EncodeSink extends ChunkedConversionSink<JsonStreamingEvent> {
  final bool isImplicitArray;
  final Sink<List<int>> _outSink;

  final List _path = [];
  dynamic _topMostElement;
  bool _thisContextHasHadOneElement = false;
  bool _isTop = true;
  bool _isBottom = false;
  bool _isInObject;

  _JsonUtf8EncodeSink(this._outSink, this.isImplicitArray) {
    _isInObject = isImplicitArray ? false : null;
  }

  @override
  void add(JsonStreamingEvent chunk) {
    //print(chunk);
    if (_isBottom) {
      throw new StateError("Stream was closed when we received an event");
    } else if (_isTop && !isImplicitArray && chunk.path.length > 0) {
      throw new StateError("Unexpected path on json Stream ${chunk.path}");
    } else if (chunk.eventType != JsonStreamingEventType.close) {
      if (!_isTop || isImplicitArray) {
        if (chunk.path.length != _path.length + 1) {
          throw new StateError("Unexpected path on json Stream ${chunk.path}");
        }
        var i;
        for (i = 0; i < _path.length; i++) {
          if (chunk.path[i] != _path[i]) {
            throw new StateError(
                "Unexpected path on json Stream ${chunk.path}");
          }
        }
        final pathElementToAdd = chunk.path[i];
        if (_isInObject && pathElementToAdd is! String) {
          if (chunk.path[i] != _path[i]) {
            throw new StateError(
                "Unexpected path on json Stream ${chunk.path}");
          }
        } else if (!_isInObject && pathElementToAdd is! int) {
          if (chunk.path[i] != _path[i]) {
            throw new StateError(
                "Unexpected path on json Stream ${chunk.path}");
          }
        }
        if (_thisContextHasHadOneElement) {
          _addSymbol(44);
        }
        if (chunk.eventType == JsonStreamingEventType.open) {
          _path.add(pathElementToAdd);
        }
        if (pathElementToAdd is String) {
          _dumpString(pathElementToAdd);
          _addSymbol(58); // :
        }
      }
      if (chunk.eventType == JsonStreamingEventType.open) {
        _thisContextHasHadOneElement = false;
        _isInObject = (chunk.boxType == JsonStreamingBox.object);
      } else {
        _thisContextHasHadOneElement = true;
      }
      _isTop = false;
      _dumpToSink(chunk);
    } else { //it's a close event
      var i;
      for (i = 0; i < _path.length; i++) {
        if (chunk.path[i] != _path[i]) {
          throw new StateError("Unexpected path on json Stream ${chunk.path}");
        }
      }
      _dumpToSink(chunk);
      if (_path.length == 0 && isImplicitArray) {
        _thisContextHasHadOneElement = false;
        _isTop = true;
      } else if (_path.length == 0) {
        if (isImplicitArray) {
          _isTop = true;
          _thisContextHasHadOneElement = false;
        } else {
          _isBottom = true;
        }
      } else {
        final pathElementToRemove = chunk.path[i - 1];
        if (pathElementToRemove is String) {
          _isInObject = true;
        } else {
          _isInObject = false;
        }
        _path.removeLast();
      }
    }
  }

  void _addSymbol(int i) {
    _outSink.add([i]);
  }

  @override
  void close() {
    if ((isImplicitArray && _isTop) || _isBottom) _outSink.close();
    throw new StateError("Json stream closed prematurely");
  }

  static const _escapeKeys = const {8:98,12:102,10:110,13:114,9:116};

  void _dumpString(String input) {
    final result = [34];
    for (var unit in input.codeUnits) {
      if (const [34,92,47].contains(unit)) {
        result.addAll([92, unit]);
      } else if (_escapeKeys.containsKey(unit)) {
        result.addAll([92, _escapeKeys[unit]]);
      } else if (unit < 32) {
        result.addAll([92, 117, 48, 48, unit ~/ 16, unit % 16]);
      } else if (unit > 0x10000) {
        var byte1 = (unit >> 18) & 7 | 0xF0;
        var byte2 = (unit >> 12) & 63 | 0x80;
        var byte3 = (unit >> 6) & 63 | 0x80;
        var byte4 = (unit) & 63 | 0x80;
        result.addAll([byte1, byte2, byte3, byte4]);
      } else if (unit > 0x800) {
        var byte1 = (unit >> 12) & 15 | 0xE0;
        var byte2 = (unit >> 6) & 63 | 0x80;
        var byte3 = (unit) & 63 | 0x80;
        result.addAll([byte1, byte2, byte3]);
      } else if (unit > 0x80) {
        var byte2 = (unit >> 6) & 31 | 0xC0;
        var byte3 = (unit) & 63 | 0x80;
        result.addAll([ byte2, byte3]);
      } else {
        result.add(unit);
      }
    }
    result.add(34);
    _outSink.add(result);
  }

  void _dumpToSink(JsonStreamingEvent chunk) {
    if (chunk.boxType == JsonStreamingBox.na) {
      if (chunk.symbol == null) {
        _outSink.add([110,117,108,108]); //null
      } else if (chunk.symbol is bool && chunk.symbol) {
        _outSink.add([116,114,117,101]); //true
      } else if (chunk.symbol is bool) {
        _outSink.add([102,97,108,115,101]); //false
      } else if (chunk.symbol is String) {
        _dumpString(chunk.symbol);
      } else if (chunk.symbol is num) {
        _outSink.add(chunk.symbol.toString().codeUnits); //Numbers will always be ascii
      } else {
        throw new StateError("Unsupported chunk type");
      }
    } else if (chunk.boxType == JsonStreamingBox.object && chunk.eventType == JsonStreamingEventType.open) {
      _outSink.add([123]);
    } else if (chunk.boxType == JsonStreamingBox.array && chunk.eventType == JsonStreamingEventType.open) {
      _outSink.add([91]);
    } else if (chunk.boxType == JsonStreamingBox.object && chunk.eventType == JsonStreamingEventType.close) {
      _outSink.add([125]);
    } else if (chunk.boxType == JsonStreamingBox.array && chunk.eventType == JsonStreamingEventType.close) {
      _outSink.add([93]);
    } else {
      throw new StateError("Unsupported chunk type");
    }
  }
}

/// This class provides json decoding.
///
/// It converts from a list of bytes in a UTF-8 encoded bytestream to either
/// a) the corresponding object in non-chunked form or b)
/// a series of [JsonStreamingEvent]
class JsonUtf8StreamDecoder
    extends ChunkedConverter<List<int>, dynamic, List<int>, JsonStreamingEvent> {
  final bool isImplicitArray;

  const JsonUtf8StreamDecoder(this.isImplicitArray);

  @override
  dynamic convert(List<int> input) {
    var finalValue = new _TakeLastSink<JsonStreamingEvent>();
    var incoming = startChunkedConversion(finalValue);
    incoming.add(input);
    incoming.close();
    if (finalValue.value.path.length != 0 || finalValue.value.eventType == JsonStreamingEventType.open) {
      throw new StateError("Received an incomplete json stream");
    }
    return finalValue.value.symbol;
  }

  @override
  ByteConversionSink startChunkedConversion(
          Sink<JsonStreamingEvent> sink) =>
      new _JsonUtf8DecodeSink(sink, isImplicitArray);
}

class _JsonUtf8DecodeSink extends ByteConversionSink with ByteConversionSinkBase {
  final Sink<JsonStreamingEvent> _outSink;

  bool _weAreInObject = false;
  bool _weAreInArray = false;
  bool _weAreInImplicitArray = false;
  bool _requireComma = false;
  bool _requireColon = false;
  bool _requireKey = false;
  int _currentKey = 0;
  String _lastKeyString = null;
  String _lastValueString = null;
  List _currentContexts = new List();
  Object _currentContext;

  _SubParser _subParser = _SubParser.begin;

  bool _hasHadDecimal;
  bool _hasHadExponent;

  Completer _stringIsReady;
  StringBuffer _stringBuffer;
  Completer _rawTokenResult;

  StringBuffer _numberResult;
  Completer _numberIsReady;

  List _currentPath;
  final bool _isImplicitArray;

  bool _isWhitespace(int symbol) {
    switch (symbol) {
      case 32:
      case 9:
      case 10:
      case 11:
      case 12:
      case 13:
        return true;
      default:
        return false;
    }
  }

  /// Close the stream
  @override
  void close() => _handleEof();

  void _handleEof() {
    if ((_subParser == _SubParser.end || _subParser == _SubParser.errored) ||
        (_isImplicitArray && _subParser == _SubParser.begin)) {
      _outSink.close();
    } else {
      throw new StateError("Received unexpected EOF");
    }
  }

  void _handleToken(int ch) {
    switch (_subParser) {
      case _SubParser.begin:
        return _handleBeginSymbol(ch);
      case _SubParser.top:
        return _handleTopSymbol(ch);
      case _SubParser.end:
        return _handleEndSymbol(ch);
      case _SubParser.numberPart1:
        return _handleNumberAtNegative(ch);
      case _SubParser.numberPart2:
        return _handleNumberNoNegative(ch);
      case _SubParser.numberPart3:
        return _handleNumberExponent(ch);
      case _SubParser.numberPart4:
        return _handleNumberExponentInitialDigit(ch);
      case _SubParser.string:
        return _handleString(ch);
      case _SubParser.rawToken:
        return _handleNextSymbol(ch);
      case _SubParser.errored:
        break;
    }
  }

  void _handleBeginSymbol(int ch) {
    if (_isWhitespace(ch)) return;
    if (ch == 123) {
      // Open brace {
      if (!_weAreInImplicitArray) {
        _currentPath = new List();
      } else {
        _weAreInImplicitArray = false;
      }
      _currentContext = new Map();
      _currentContexts.add(_currentContext);

      _outSink.add(new JsonStreamingEvent(JsonStreamingBox.object, _currentPath, _currentContext, JsonStreamingEventType.open));
      _subParser = _SubParser.top;
      _weAreInObject = true;
      _requireKey = true;
      return;
    } else {
      try {
        _parserAssertNotReached("Expected {");
      } catch (err) {
        _subParser = _SubParser.errored;
        rethrow;
      }
    }
  }

  void _handleEndSymbol(int ch) {
    if (_isWhitespace(ch))
      return;
    else {
      _subParser = _SubParser.errored;
      throw new StateError("Expected WHITESPACE");
    }
  }

  void _handleTopSymbol(int ch) {
    if (_isWhitespace(ch)) return;
    if (_weAreInImplicitArray) {
      _subParser = _SubParser.errored;
      throw new StateError("Expected WHITESPACE or { ");
    } else if (_weAreInObject && (_requireComma || _requireKey) && ch == 125) {
      //Close brace }
      _outSink.add(new JsonStreamingEvent(JsonStreamingBox.object, _currentPath, _currentContext, JsonStreamingEventType.close));
      if (_currentPath.length == 0) {
        _subParser = _SubParser.end;
      } else if (_currentPath.length == 1 && _isImplicitArray) {
        _weAreInObject = false;
        _requireComma = false;
        _requireKey = false;

        _weAreInImplicitArray = true;
        _subParser = _SubParser.begin;
        _currentPath[0]++;
      } else {
        var lastKey = _currentPath.removeLast();
        if (lastKey is int) {
          _weAreInObject = false;
          _weAreInArray = true;
        } else {
          assert(lastKey is String);
          _weAreInObject = true;
          _weAreInArray = false;
        }
        _requireComma = true;
        _currentContexts.removeLast();
        _currentContext = _currentContexts.last;
      }
      return;
    } else if (_weAreInObject && _requireComma && ch == 44) {
      _requireComma = false;
      _requireKey = true;
      return;
    } else if (_weAreInObject && _requireComma) {
      _parserAssertNotReached("Expected } or ,");
      _subParser = _SubParser.errored;
    } else if (_weAreInObject && _requireColon && ch == 58) {
      _requireColon = false;
      return;
    } else if (_weAreInObject && _requireColon) {
      _parserAssertNotReached("Expected :");
      _subParser = _SubParser.errored;
    } else if (_weAreInObject && _requireKey && ch == 34) {
      _stringIsReady = new Completer.sync();
      _stringBuffer = new StringBuffer();
      _subParser = _SubParser.string;

      _stringIsReady.future.then((_) {
        _stringIsReady = null;
        _stringBuffer = null;
        _subParser = _SubParser.top;

        _lastKeyString = _lastValueString;
        _requireColon = true;
        _requireKey = false;
      }, onError: (err) {
        _subParser = _SubParser.errored;
        throw err;
      });
      return;
    } else if (_weAreInObject && _requireKey) {
      _parserAssertNotReached("Expected \" or }");
      _subParser = _SubParser.errored;
      return;
    } else if (_weAreInArray && ch == 93) {
      //Close bracket ]
      _outSink.add(new JsonStreamingEvent(JsonStreamingBox.array, _currentPath, _currentContext, JsonStreamingEventType.close));
      var lastKey = _currentPath.removeLast();
      if (lastKey is int) {
        _weAreInObject = false;
        _weAreInArray = true;
      } else {
        assert(lastKey is String);
        _weAreInObject = true;
        _weAreInArray = false;
      }
      _requireComma = true;
      _currentContexts.removeLast();
      _currentContext = _currentContexts.last;
      return;
    } else if (_weAreInArray && _requireComma && ch == 44) {
      _currentKey++;
      _requireComma = false;
    } else if (_weAreInArray && _requireComma) {
      _parserAssertNotReached("Expected ] or ,");
      _subParser = _SubParser.errored;
      //Now we can accept ANY JSON value.
    } else if (ch == 123) {
      // Open brace {
      final tempContext = new Map();
      _currentContexts.add(tempContext);
      if (_weAreInObject) {
        var tempPath = _lastKeyString.toString();
        _currentPath.add(tempPath);
        (_currentContext as Map)[tempPath] = tempContext;
      } else {
        assert(_weAreInArray);
        var tempPath = this._currentKey;
        _currentPath.add(tempPath);
        (_currentContext as List).add(tempContext);
      }
      _currentContext = tempContext;
      _outSink.add(new JsonStreamingEvent(JsonStreamingBox.object, _currentPath, _currentContext, JsonStreamingEventType.open));
      _weAreInObject = true;
      _weAreInArray = false;
      _requireKey = true;
      _lastKeyString = null;
      return;
    } else if (ch == 91) {
      // Open bracket [
      final tempContext = new List();
      _currentContexts.add(tempContext);
      if (_weAreInObject) {
        var tempPath = _lastKeyString.toString();
        _currentPath.add(tempPath);
        (_currentContext as Map)[tempPath] = tempContext;
      } else {
        assert(_weAreInArray);
        var tempPath = this._currentKey;
        _currentPath.add(tempPath);
        (_currentContext as List).add(tempContext);
      }
      _currentContext = tempContext;
      _outSink.add(new JsonStreamingEvent(JsonStreamingBox.array, _currentPath, _currentContext, JsonStreamingEventType.open));
      _weAreInObject = false;
      _weAreInArray = true;
      _currentKey = 0;
      return;
    } else if (ch == 34) {
      // "
      _stringIsReady = new Completer.sync();
      _stringBuffer = new StringBuffer();

      _subParser = _SubParser.string;

      _stringIsReady.future.then((_) {
        _stringIsReady = null;
        _stringBuffer = null;

        _outSink.add(_makeFinalSymbol(_lastValueString));

        _subParser = _SubParser.top;
      }, onError: (error) {
        _subParser = _SubParser.errored;
        throw error;
      });

      return;
    } else if (ch == 116) {
      // t
      _rawTokenResult = new Completer.sync();
      _subParser = _SubParser.rawToken;
      _rawTokenResult.future.then((bufferI1) {
        // r
        _parserAssert(bufferI1 == 114, "Expected r");
        _rawTokenResult = new Completer.sync();
        return _rawTokenResult.future;
      }).then((bufferI2) {
        // u
        _parserAssert(bufferI2 == 117, "Expected u");
        _rawTokenResult = new Completer.sync();
        return _rawTokenResult.future;
      }).then((bufferI3) {
        // e
        _parserAssert(bufferI3 == 101, "Expected e");
        _outSink.add(_makeFinalSymbol(true));
        _subParser = _SubParser.top;
        _rawTokenResult = null;
      }).catchError((error) {
        _subParser = _SubParser.errored;
        throw error;
      });
      return;
    } else if (ch == 102) {
      // f
      _rawTokenResult = new Completer.sync();
      _subParser = _SubParser.rawToken;
      _rawTokenResult.future.then((bufferI1) {
        // a
        _parserAssert(bufferI1 == 97, "Expected a");
        _rawTokenResult = new Completer.sync();
        return _rawTokenResult.future;
      }).then((bufferI2) {
        // l
        _parserAssert(bufferI2 == 108, "Expected l");
        _rawTokenResult = new Completer.sync();
        return _rawTokenResult.future;
      }).then((bufferI3) {
        // s
        _parserAssert(bufferI3 == 115, "Expected s");
        _rawTokenResult = new Completer.sync();
        return _rawTokenResult.future;
      }).then((bufferI4) {
        // e
        _parserAssert(bufferI4 == 101, "Expected e");
        _outSink.add(_makeFinalSymbol(false));

        _subParser = _SubParser.top;
        _rawTokenResult = null;
      }).catchError((error) {
        _subParser = _SubParser.errored;
        throw error;
      });
      return;
    } else if (ch == 110) {
      // n
      _rawTokenResult = new Completer.sync();
      _subParser = _SubParser.rawToken;
      _rawTokenResult.future.then((bufferI1) {
        // u
        _parserAssert(bufferI1 == 117, "Expected u");
        _rawTokenResult = new Completer.sync();
        return _rawTokenResult.future;
      }).then((bufferI2) {
        // l
        _parserAssert(bufferI2 == 108, "Expected l");
        _rawTokenResult = new Completer.sync();
        return _rawTokenResult.future;
      }).then((bufferI3) {
        // l
        _parserAssert(bufferI3 == 108, "Expected l");
        _outSink.add(_makeFinalSymbol(null));

        _subParser = _SubParser.top;
        _rawTokenResult = null;
      }).catchError((error) {
        _subParser = _SubParser.errored;
        throw error;
      });
      return;
    } else if (<int>[45, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57].contains(ch)) {
      _numberResult = new StringBuffer();
      _numberIsReady = new Completer.sync();
      _numberResult.writeCharCode(ch);
      if (ch == 45) {
        _subParser = _SubParser.numberPart1;
      } else {
        _subParser = _SubParser.numberPart2;
        _hasHadDecimal = false;
        _hasHadExponent = false;
      }
      _numberIsReady.future.then((result) {
        _outSink.add(_makeFinalSymbol(result));
      }).catchError((error) {
        _subParser = _SubParser.errored;
        throw error;
      });
      return;
    } else {
      _parserAssertNotReached(
          "Expected {, [, \", -, DIGIT, WHITESPACE, null, true, or false");
    }
  }

  void _handleNumberAtNegative(ch) {
    if (<int>[48, 49, 50, 51, 52, 53, 54, 55, 56, 57].contains(ch)) {
      _numberResult.writeCharCode(ch);
    } else {
      try {
        throw new StateError("DIGIT");
      } catch (err) {
        _numberIsReady.completeError(err);
      }
    }
    _hasHadDecimal = false;
    _hasHadExponent = false;
    _subParser = _SubParser.numberPart2;
  }

  _handleNumberNoNegative(ch) {
    if (this._isWhitespace(ch) || <int>[44, 93, 125].contains(ch)) {
      var value;
      if (_hasHadDecimal) {
        value = double.parse(_numberResult.toString());
        _numberIsReady.complete(value);
      } else {
        value = int.parse(_numberResult.toString());
        _numberIsReady.complete(value);
      }
      _subParser = _SubParser.top;
      _handleTopSymbol(ch);
    } else if (!_hasHadDecimal && ch == 46) {
      _numberResult.writeCharCode(ch);
      _hasHadDecimal = true;
    } else if (ch == 46) {
      try {
        if (!_hasHadExponent) {
          throw new StateError('Expected digit or e');
        } else {
          throw new StateError('Expected digit');
        }
      } catch (error) {
        _numberIsReady.completeError(error);
      }
    } else if (!_hasHadExponent && (ch == 46 || ch == 101)) {
      // E / e
      _numberResult.writeCharCode(ch);
      _subParser = _SubParser.numberPart3;
    } else if (ch == 46 || ch == 101) {
      try {
        throw new StateError('Expected digit');
      } catch (err) {
        _numberIsReady.completeError(err);
      }
    } else if (<int>[48, 49, 50, 51, 52, 53, 54, 55, 56, 57].contains(ch)) {
      _numberResult.writeCharCode(ch);
    } else {
      try {
        throw new StateError("Expected NUMBER PART");
      } catch (err) {
        _numberIsReady.completeError(err);
      }
    }
  }

  _handleNumberExponent(ch) {
    if (ch == 45 || ch == 43) {
      _numberResult.writeCharCode(ch);
      _subParser = _SubParser.numberPart4;
    } else if (<int>[48, 49, 50, 51, 52, 53, 54, 55, 56, 57].contains(ch)) {
      _numberResult.writeCharCode(ch);
      _hasHadExponent = true;
      _hasHadDecimal = true;
      _subParser = _SubParser.numberPart2;
    } else {
      try {
        throw new StateError("Expected DIGIT, +, or -");
      } catch (err) {
        _numberIsReady.completeError(err);
      }
    }
  }

  _handleNumberExponentInitialDigit(ch) {
    if (<int>[48, 49, 50, 51, 52, 53, 54, 55, 56, 57].contains(ch)) {
      _numberResult.writeCharCode(ch);
      _hasHadExponent = true;
      _hasHadDecimal = true;
      _subParser = _SubParser.numberPart2;
    } else {
      try {
        _parserAssertNotReached("Expected DIGIT");
      } catch (err) {
        _numberIsReady.completeError(err);
      }
    }
  }

  void _parserAssertNotReached(String message) {
    _subParser = _SubParser.errored;
    throw new StateError(message);
  }

  JsonStreamingEvent _makeFinalSymbol(value) {
    if (_weAreInObject) {
      var tempPath = _lastKeyString.toString();
      _currentPath.add(tempPath);
      (_currentContext as Map)[tempPath] = value;
    } else {
      assert(_weAreInArray);
      var tempPath = this._currentKey;
      _currentPath.add(tempPath);
      (_currentContext as List).add(value);
    }
    var result = new JsonStreamingEvent(JsonStreamingBox.na, _currentPath, value, JsonStreamingEventType.token);
    _currentPath.removeLast();
    _requireComma = true;
    return result;
  }

  bool _parserAssert(bool condition, String message) {
    if (!condition) {
      throw new StateError(message);
      return true;
    }
    return false;
  }

  void _handleNextSymbol(int ch) => _rawTokenResult.complete(ch);

  void _handleString(ch) {
    if (ch == 34) {
      _lastValueString = _stringBuffer.toString();
      _subParser = _SubParser.top;
      _stringIsReady.complete();
    } else if (ch == 92) {
      _rawTokenResult = new Completer.sync();
      _subParser = _SubParser.rawToken;
      _rawTokenResult.future.then((nextBufferCode) {
        if (nextBufferCode == 34 ||
            nextBufferCode == 92 ||
            nextBufferCode == 47) {
          _stringBuffer.writeCharCode(nextBufferCode);
        } else {
          switch (nextBufferCode) {
            case 98:
              _stringBuffer.writeCharCode(8);
              break;
            case 102:
              _stringBuffer.writeCharCode(12);
              break;
            case 110:
              _stringBuffer.writeCharCode(10);
              break;
            case 114:
              _stringBuffer.writeCharCode(13);
              break;
            case 116:
              _stringBuffer.writeCharCode(9);
              break;
            case 117:
              _rawTokenResult = new Completer.sync();
              _rawTokenResult.future.then((bufferI1) {
                _rawTokenResult = new Completer.sync();
                _rawTokenResult.future.then((bufferI2) {
                  _rawTokenResult = new Completer.sync();
                  _rawTokenResult.future.then((bufferI3) {
                    _rawTokenResult = new Completer.sync();
                    _rawTokenResult.future.then((bufferI4) {
                      _stringBuffer.writeCharCode(int.parse(
                          new AsciiDecoder().convert(
                              [bufferI1, bufferI2, bufferI3, bufferI4]),
                          radix: 16));
                      _subParser = _SubParser.string;
                      _rawTokenResult = null;
                    });
                  });
                });
              }).catchError((error) {
                _subParser = _SubParser.errored;
                throw error;
              });
              return; // Because we'll still use the token subparser
            default:
              _stringBuffer.writeCharCode(nextBufferCode);
          }
        }
        _subParser = _SubParser.string;
      });
    } else if (ch == 10 || ch == 13) {
      _subParser = _SubParser.top;
      throw new StateError("Expected \" but found EOL");
    } else {
      _stringBuffer.writeCharCode(ch);
    }
  }

  _JsonUtf8DecodeSink(this._outSink, [this._isImplicitArray = false]);

  /// Convert a slice of tokens.
  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    for (int i = start; i < end; i++) {
      _handleToken(chunk[i]);
    }
    if (isLast) close();
  }

  @override
  void add(List<int> symbolBuffer) {
    addSlice(symbolBuffer, 0, symbolBuffer.length, false);
  }
}

/// Static class that provides the static functions for compatability.
///
/// This is now deprecated in favor of the new ChunkedConversion interface.
@deprecated
class JsonStreamingParser {
  static Stream<JsonStreamingEvent> streamTransform(Stream<int> input) => new JsonStreamTransformer().bind(input);
}

/// Stream transformer version of the chunked conversion above, mostly provided
/// for backward compatability.
@deprecated
class JsonStreamTransformer
    implements StreamTransformer<int, JsonStreamingEvent> {
  final bool isImplicitArray;
  Stream<JsonStreamingEvent> bind(Stream<int> inputStream) {
    var controller = new StreamController<JsonStreamingEvent>();
    var decoder = new _JsonUtf8DecodeSink(controller.sink, isImplicitArray);
    inputStream.listen(
        (data) => decoder.add([data]),
        onError: (err, stackTrace) => controller.addError(err, stackTrace),
        onDone: () => decoder.close());
    return controller.stream;
  }
  const JsonStreamTransformer([bool this.isImplicitArray = false]);
}

class _TakeLastSink<T> extends Sink<T> {
  bool _hasValue = false;
  T _value;
  T get value {
    if (!_hasValue) {
      throw new StateError("Sink did not receive a value");
    }
    return _value;
  }


  @override
  void add(T data) {
    _value = data;
    _hasValue = true;
  }

  @override
  void close() {}
}

