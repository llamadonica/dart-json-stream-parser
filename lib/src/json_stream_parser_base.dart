// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

// TODO: Put public facing types in this file.

library json_stream_parser.base;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:collection';

import 'dart:io';

import 'package:quiver/core.dart';

const int _OPEN_BRACE = 123;
const int _CLOSE_BRACE = 125;
const int _OPEN_BRACKET = 91;
const int _CLOSE_BRACKET = 93;
const int _COMMA = 0x2C;
const int _COLON = 0x3A;

const int _SPACE = 0x20;
const int _TAB = 0x09;
const int _LINE_FEED = 0x0A;
const int _CARRIAGE_RETURN = 0x0D;

const int _U_CHAR = 0x75;

const int _BACKSLASH = 92;
const int _QUOTE = 34;

const int _B_CHAR = 0x62;
const int _F_CHAR = 0x66;
const int _N_CHAR = 0x6E;
const int _T_CHAR = 0x74;
const int _R_CHAR = 0x72;

abstract class JsonUtf8DecodeSinkFast extends ByteConversionSink {
  final Sink<JsonStreamingEventFast> _outSink;

  factory JsonUtf8DecodeSinkFast(Sink<JsonStreamingEventFast> sink) =>
      new _JsonUtf8DecodeSinkFast(sink);
  JsonUtf8DecodeSinkFast._(this._outSink);
}

abstract class JsonUtf8EncodeSinkFast
    extends ChunkedConversionSink<JsonStreamingEventFast> {
  final Sink<List<int>> _outSink;

  factory JsonUtf8EncodeSinkFast(Sink<List<int>> sink) =>
      new _JsonUtf8EncodeSinkFast(sink);
  JsonUtf8EncodeSinkFast._(this._outSink);
}

class _JsonUtf8DecodeSinkFast extends JsonUtf8DecodeSinkFast
    with ByteConversionSinkBase {
  static const List<int> MINIMAL_ESCAPES = const [
    _BACKSLASH,
    _QUOTE,
    _B_CHAR,
    _F_CHAR,
    _N_CHAR,
    _R_CHAR,
    _T_CHAR
  ];

  bool _isInString = false; //We're in a string
  bool _isInToken = false; //We're
  bool _lastWasBackslash = false;
  bool _isInObject = false;
  bool _isInKeyPart = false;
  bool _didEmitTerminalSignal = false;
  final List<bool> _objectStack = new List();

  _JsonUtf8DecodeSinkFast(Sink<JsonStreamingEventFast> sink) : super._(sink);

  @override
  void add(List<int> chunk) {
    _processChunk(chunk);
  }

  void _processChunk(List<int> chunk) {
    int offset = 0;
    while (offset < chunk.length) {
      if (_isInString) {
        offset = _processsStringPart(chunk, offset);
      } else if (_isInToken) {
        offset = _processOther(chunk, offset);
      } else {
        offset = _processTop(chunk, offset);
      }
    }
    if (!_didEmitTerminalSignal)
      _emitPart(null, false, false, false, false, false, false, false, chunk,
          chunk.length, 0);
  }

  int _processOther(List<int> chunk, int offset, [bool isStart = false]) {
    var offsetStart = offset;
    if (isStart) {
      _isInToken = true;
    }
    for (; offset < chunk.length; offset++) {
      switch (chunk[offset]) {
        case _SPACE:
        case _TAB:
        case _LINE_FEED:
        case _CARRIAGE_RETURN:
        case _OPEN_BRACE:
        case _CLOSE_BRACE:
        case _OPEN_BRACKET:
        case _CLOSE_BRACKET:
        case _COMMA:
        case _QUOTE:
          _emitPart(
              _objectStack.length,
              false,
              false,
              false,
              false,
              _isInKeyPart,
              true,
              false,
              chunk,
              offsetStart,
              offset - offsetStart);
          _isInToken = false;
          return _processTop(chunk, offset);
      }
    }
    //We reached the end and it's not clear whether we reached the end of the
    //stream so emit what we have.
    _emitPart(_objectStack.length, false, false, false, false, _isInKeyPart,
        true, false, chunk, offsetStart, offset - offsetStart);
    return offset;
  }

  int _processsStringPart(List<int> chunk, int offset, [bool isStart = false]) {
    var offsetStart = offset;
    if (isStart) {
      offset++;
      _isInString = true;
      _lastWasBackslash = false;
    }
    for (; offset < chunk.length; offset++) {
      switch (chunk[offset]) {
        case _BACKSLASH:
          if (offset + 1 >= chunk.length) {
            _lastWasBackslash = true;
            _emitPart(
                _objectStack.length + 1,
                false,
                false,
                false,
                false,
                _isInKeyPart,
                true,
                true,
                chunk,
                offsetStart,
                chunk.length - offsetStart);
            return chunk.length;
          } else {
            //Skip the next symbol
            offset++;
          }
          break;
        case _QUOTE:
          {
            if (_lastWasBackslash) break;
            _emitPart(
                _objectStack.length,
                false,
                false,
                false,
                false,
                _isInKeyPart,
                true,
                true,
                chunk,
                offsetStart,
                offset - offsetStart + 1);
            _isInString = false;
            _lastWasBackslash = null;
          }
          return offset + 1;
      }
      _lastWasBackslash = false;
    }
    // We reached the end of the string and no quote marker, so emit what we have.
    _emitPart(_objectStack.length + 1, false, false, false, false, _isInKeyPart,
        true, true, chunk, offsetStart, offset - offsetStart);
    return offset;
  }

  List<int> _getSubString(chunk, start, length) {
    if (chunk is Uint8List) {
      return new Uint8List.view(
          chunk.buffer, start + chunk.offsetInBytes, length);
    } else {
      return new _ListView<int>(chunk, start, length);
    }
  }

  int _processTop(List<int> chunk, int offset) {
    switch (chunk[offset]) {
      case _SPACE:
      case _TAB:
      case _LINE_FEED:
      case _CARRIAGE_RETURN:
        return offset + 1;
      case _OPEN_BRACE:
        {
          _objectStack.add(true);
          _isInKeyPart = true;
          _isInObject = true;
          _emitPart(_objectStack.length, true, false, false, false, false,
              false, false, chunk, offset, 1);
        }
        return offset + 1;
      case _CLOSE_BRACE:
        {
          _objectStack.removeLast();
          if (_objectStack.isEmpty) {
            _isInObject = false;
          } else {
            _isInObject = _objectStack.last;
          }
          _isInKeyPart = _isInObject;
          _emitPart(_objectStack.length, true, false, false, false, false,
              false, false, chunk, offset, 1);
        }
        return offset + 1;
      case _OPEN_BRACKET:
        {
          _objectStack.add(false);
          _emitPart(_objectStack.length, false, true, false, false, false,
              false, false, chunk, offset, 1);
          _isInKeyPart = false;
          _isInObject = false;
        }
        return offset + 1;
      case _CLOSE_BRACKET:
        {
          _objectStack.removeLast();
          if (_objectStack.isEmpty) {
            _isInObject = false;
          } else {
            _isInObject = _objectStack.last;
          }
          _isInKeyPart = _isInObject;
          _emitPart(_objectStack.length, false, true, false, false, false,
              false, false, chunk, offset, 1);
        }
        return offset + 1;
      case _COMMA:
        {
          _isInKeyPart = _isInObject;
          _emitPart(_objectStack.length, false, false, true, false, false,
              false, false, chunk, offset, 1);
        }
        return offset + 1;
      case _COLON:
        {
          _isInKeyPart = false;
          _emitPart(_objectStack.length, false, false, false, true, false,
              false, false, chunk, offset, 1);
        }
        return offset + 1;
      case _QUOTE:
        return _processsStringPart(chunk, offset, true);
      default:
        return _processOther(chunk, offset, true);
    }
  }

  void _emitPart(symbolLevel, isBrace, isBracket, isComma, isColon, inKeyPhase,
      isSymbol, isString, List<int> chunk, offset, length) {
    List<int> emittedChunk = _getSubString(chunk, offset, length);
    _didEmitTerminalSignal = offset + length == chunk.length;
    _outSink.add(new JsonStreamingEventFast(
        symbolLevel,
        isBrace,
        isBracket,
        isComma,
        isColon,
        inKeyPhase,
        isSymbol,
        isString,
        _isInObject,
        emittedChunk,
        _didEmitTerminalSignal));
  }

  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    if (chunk is TypedData &&
        (chunk is Uint8List ||
            chunk is Int8List ||
            chunk is Uint8ClampedList)) {
      //do a fast-ish copy.
      chunk = fastCopy(chunk as TypedData, start, end);
    } else {
      var newChunk = new Uint8List(end - start);
      var j = 0;
      for (var i = start; i < end; i++) {
        newChunk[j] = chunk[i];
      }
    }
    _processChunk(chunk);
    if (isLast) close();
  }

  @override
  void close() {
    _outSink.close();
  }
}

class _JsonUtf8EncodeSinkFast extends JsonUtf8EncodeSinkFast {
  _JsonUtf8EncodeSinkFast(Sink<List<int>> sink) : super._(sink);
  _ByteBuilder __byteBuilder;
  _ByteBuilder get _byteBuilder {
    if (__byteBuilder == null) {
      __byteBuilder = new _ByteBuilder();
    }
    return __byteBuilder;
  }

  @override
  void add(JsonStreamingEventFast chunk) {
    var chunkData = chunk.bytestream;
    if (chunkData is Uint8List) {
      _byteBuilder.appendChunk(chunkData);
    } else {
      _byteBuilder.appendChunk(new Uint8List.fromList(chunkData));
    }
    if (chunk.isEndOfStream) {
      _emit();
    }
  }

  void _emit() {
    _outSink.add(_byteBuilder.toUint8List());
    __byteBuilder = null;
  }

  @override
  void close() {
    _outSink.close();
  }
}

class JsonStreamingEventFast {
  final int
      symbolLevel; //+1 means it's the beginning of an entity, -1 means it's the end.
  final bool isBrace;
  final bool isBracket;
  final bool isComma;
  final bool isColon;
  final bool isSymbol;
  final bool isString;
  final bool inKeyPhase;
  final bool isEndOfStream;
  final bool isInObject;
  final List<int> bytestream;

  JsonStreamingEventFast(
      this.symbolLevel,
      this.isBrace,
      this.isBracket,
      this.isComma,
      this.isColon,
      this.inKeyPhase,
      this.isSymbol,
      this.isString,
      this.isInObject,
      this.bytestream,
      this.isEndOfStream);
}

class _ByteBuilder {
  List<Uint8List> _dataParts = [];
  int length = 0;

  void appendChunk(Uint8List chunk) {
    if (chunk.length > 0) {
      _dataParts.add(chunk);
      length += chunk.length;
    }
  }

  Uint8List toUint8List() {
    if (_dataParts.length == 1) return _dataParts[0];
    var newBuffer = new Uint8List(length);
    if (_dataParts.length == 0) return newBuffer;
    var offset = 0;
    for (var buffer in _dataParts) {
      newBuffer.setRange(offset, offset + buffer.length, buffer);
      offset += buffer.length;
    }
    _dataParts = [];
    if (offset != 0) {
      _dataParts.add(newBuffer);
    }
    return newBuffer;
  }
}

class _ListView<T> extends ListBase<T> with ListMixin<T> implements List<T> {
  final List<T> _baseView;
  final int _offset;
  int _length;

  @override
  int get length => _length;

  @override
  set length(int newLength) {
    if (_baseView.length - _offset < newLength) {
      throw new RangeError.range(newLength, 0, _baseView.length - _offset);
    }
    _length = newLength;
  }

  _ListView(this._baseView, this._offset, this._length) {
    if (_baseView.length - _offset < _length) {
      throw new RangeError.range(_length, 0, _baseView.length - _offset);
    }
  }

  @override
  T operator [](int index) {
    if (index >= _length) throw new RangeError.range(index, 0, _length - 1);
    return _baseView[index + _offset];
  }

  @override
  void operator []=(int index, T value) {
    if (index >= _length) throw new RangeError.range(index, 0, _length - 1);
    _baseView[index + _offset] = value;
  }
}

class PathSetterDecoderSink
    extends ChunkedConversionSink<JsonStreamingEventFast> {
  final Sink<PathSetterEvent> _outSink;
  var _lastKey = -1;
  var _thisKey = null;
  var _lastLevel = 0;
  final List<dynamic> _path = [];
  _ByteBuilder __buffer;
  _ByteBuilder get _buffer {
    if (__buffer == null) {
      __buffer = new _ByteBuilder();
    }
    return __buffer;
  }

  PathSetterDecoderSink(this._outSink);

  @override
  void add(JsonStreamingEventFast chunk) {
    if (chunk.symbolLevel == null) return;
    if (chunk.isColon || chunk.isComma) return; // Nothing to do.
    if (chunk.symbolLevel < _lastLevel) {
      _lastKey = _path.removeLast();
      _lastLevel--;
      _emitPop();
    } else if ((chunk.isBrace || chunk.isBracket) &&
        chunk.symbolLevel > _lastLevel) {
      _emitNewContainer(chunk.isBrace);
    } else if (chunk.isSymbol) {
      _buffer.appendChunk(chunk.bytestream);
      if (chunk.symbolLevel == _lastLevel) {
        var symbolBuffer = _buffer;
        __buffer = null;
        if (chunk.inKeyPhase) {
          _thisKey = _parseSymbol(symbolBuffer.toUint8List());
        }
        else {
          if (_thisKey == null) {
            _lastKey = _thisKey = _lastKey + 1;
          }
          _outSink.add(new PathSetterEvent(_path.toList()..add(_thisKey), _thisKey, _parseSymbol(symbolBuffer.toUint8List()), PathSetterNavigation.stay));
          _thisKey = null;
        }
      }
    }
  }

  static const utf8Decoder = const Utf8Decoder();
  static const jsonDecoder = const JsonDecoder();

  dynamic _parseSymbol(List<int> symbolBuffer) {
    return jsonDecoder.convert(utf8Decoder.convert(symbolBuffer));
  }

  Iterable<int> _charCodesFromRune(int rune) sync* {
    if (rune < 0x10000) {
      yield rune;
    } else {
      rune -= 0x10000;
      yield 0xD800 | (rune >> 10);
      yield 0xDC00 | (rune & 0x03FF);
    }
  }

  void _emitNewContainer(bool isObject) {
    if (_lastKey is num) {
      _lastKey++;
    } else {
      _lastKey = _thisKey;
      _thisKey = null;
    }
    _path.add(_lastKey);
    _lastLevel++;
    _outSink.add(new PathSetterEvent(_path.toList(), _lastKey,
        null, PathSetterNavigation.push, isNewObject: isObject, isNewArray: !isObject));
    if (isObject) {
      _lastKey = '';
    } else {
      _lastKey = -1;
    }
  }

  void _emitPop() {
    _outSink.add(new PathSetterEvent(
        _path.toList(), null, null, PathSetterNavigation.pop));
  }

  @override
  void close() {
    _outSink.close();
  }
}

class PathReviver extends Sink<PathSetterEvent> implements Future<dynamic> {
  final bool isMultiple;
  final Completer<dynamic> _completer = new Completer.sync();

  final List<dynamic> _stack = new List();
  dynamic _context = null;

  dynamic get context => _context;

  dynamic newArray([PathSetterEvent event]) => [];
  dynamic newObject(PathSetterEvent event) => {};

  void set(PathSetterEvent event, dynamic elementToInsert) {
    if (event.relativePath is num) {
      context.add(elementToInsert);
    } else {
      context[event.relativePath] = elementToInsert;
    }
  }

  PathReviver({this.isMultiple: false}) {
    _context = newArray();
    _stack.add(_context);
  }

  @override
  void add(PathSetterEvent data) {
      if (data.navigationDirection == PathSetterNavigation.stay) {
        set(data, data.elementToInsert);
      } else if (data.navigationDirection == PathSetterNavigation.push) {
        var elementToInsert = data.isNewArray ? newArray(data) : newObject(
            data);
        set(data, elementToInsert);
        _context = elementToInsert;
        _stack.add(_context);
      } else {
        _stack.removeLast();
        _context = _stack.last;
      }
  }

  @override
  Stream asStream() => _completer.future.asStream();

  @override
  Future catchError(Function onError, {bool test(Object error)}) =>
      _completer.future.catchError(onError, test: test);

  @override
  void close() {
    if (isMultiple) {
      _completer.complete(_stack[0]);
    } else {
      assert(_stack[0].length == 1);
      _completer.complete(_stack[0][0]);
    }
  }

  @override
  Future then(onValue(value), {Function onError}) =>
      _completer.future.then(onValue, onError: onError);

  @override
  Future timeout(Duration timeLimit, {onTimeout()}) =>
      _completer.future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future whenComplete(action()) =>
      _completer.future.whenComplete(action);
}

enum PathSetterNavigation { stay, push, pop }

class PathSetterEvent {
  final List<dynamic> fullPath;
  final dynamic relativePath;
  final dynamic elementToInsert;
  final bool isNewObject;
  final bool isNewArray;
  final PathSetterNavigation navigationDirection;

  PathSetterEvent(this.fullPath, this.relativePath, this.elementToInsert,
      this.navigationDirection,
      {this.isNewObject: false, this.isNewArray: false});
  String toString() => navigationDirection == PathSetterNavigation.pop ? 'POP!!' : '${fullPath.join(".")} → $elementToInsert';
}

Uint8List fastCopy(TypedData chunk, int start, int end) {
  var offset = chunk.offsetInBytes + start;
  var nextPos = chunk.offsetInBytes + end;

// Round down to the nearest 16 byte segment safely
  var startChunk = (((offset ^ 0x7) | 0x7) ^ 0x7);

  var trueBufferLength = chunk.buffer.lengthInBytes;
  var lastBigChunk = (((trueBufferLength ^ 0x7) | 0x7) ^ 0x7);

  var endChunk = (((nextPos ^ 0x7) | 0x7) ^ 0x7);
  nextPos &= 0x7;
  nextPos = (nextPos | (nextPos << 1)) & 0x6;
  nextPos = (nextPos | (nextPos << 1)) & 0x4;
  endChunk += nextPos << 1;

  bool do32Bit = false;
  bool do16Bit = false;
  bool do8Bit = false;

//Do we need to do any less efficient transfers?
  if (lastBigChunk < endChunk) {
    do32Bit = (trueBufferLength & 0x4) != 0;
    do16Bit = (trueBufferLength & 0x2) != 0;
    do8Bit = (trueBufferLength & 0x1) != 0;
  } else {
    lastBigChunk = endChunk;
  }

  var fromBuffer = new Int64List.view(
      chunk.buffer, startChunk, (lastBigChunk - startChunk) >> 3);
  var toBuffer = new Int64List((endChunk - startChunk) >> 3);

  lastBigChunk >>= 3;
  startChunk >>= 3;
  var j = lastBigChunk - startChunk;
  var i = lastBigChunk;
  toBuffer.setRange(0, lastBigChunk - startChunk, fromBuffer, startChunk);
  i <<= 1;
  j <<= 1;
  if (do32Bit) {
    toBuffer.buffer.asUint32List()[j] = fromBuffer.buffer.asUint32List()[i];
    i++;
    j++;
  }
  i <<= 1;
  j <<= 1;
  if (do16Bit) {
    toBuffer.buffer.asUint16List()[j] = fromBuffer.buffer.asUint16List()[i];
    i++;
    j++;
  }
  i <<= 1;
  j <<= 1;
  if (do8Bit) {
    toBuffer.buffer.asUint8List()[j] = fromBuffer.buffer.asUint8List()[i];
    i++;
    j++;
  }
  var offsetInBytes = offset & 0xF;
  var lengthInBytes = end - start;
  return toBuffer.buffer.asUint8List(offsetInBytes, lengthInBytes);
}


