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

class JsonStreamTransformer
    implements StreamTransformer<int, JsonStreamingEvent> {
  final bool isImplicitArray;
  Stream<JsonStreamingEvent> bind(Stream<int> inputStream) =>
      JsonStreamingParser.streamTransform(inputStream, isImplicitArray);
  const JsonStreamTransformer([bool this.isImplicitArray = false]);
}

//TODO: Rewrite this to make use of the Fetch and Streams API so less of the
//request has to stay resident.
class JsonStreamingParser {
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

  StreamSubscription<int> _subscription;

  JsonStreamingParser._([bool this._isImplicitArray = false]) {
    _weAreInImplicitArray = _isImplicitArray;
    if (_weAreInImplicitArray) {
      _currentPath = [0];
    }
  }

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

  static Stream<JsonStreamingEvent> streamTransform(Stream<int> symbolBuffer,
      [bool isImplicitArray = false]) {
    final parser = new JsonStreamingParser._(isImplicitArray);
    final result = new StreamController();
    parser._subscription = symbolBuffer.listen(
        (ch) => parser._handleToken(ch, result),
        onDone: () => parser._handleEof(result), onError: (err) {
      result.addError(err);
      parser._subParser = _SubParser.errored;
    });

    result.onPause = parser._subscription.pause;
    result.onResume = parser._subscription.resume;
    result.onCancel = parser._subscription.cancel;

    return result.stream;
  }

  void _handleTopSymbolEof() {
    throw new StateError("Received unexpected EOF");
  }

  void _handleEof(StreamController outputController) {
    if ((_subParser == _SubParser.end || _subParser == _SubParser.errored) ||
        (_isImplicitArray && _subParser == _SubParser.begin)) {
      outputController.close();
    } else {
      outputController.addError(new StateError("Received unexpected EOF"));
      outputController.close();
    }
  }

  void _handleToken(int ch, StreamController outputController) {
    switch (_subParser) {
      case _SubParser.begin:
        return _handleBeginSymbol(ch, outputController);
      case _SubParser.top:
        return _handleTopSymbol(ch, outputController);
      case _SubParser.end:
        return _handleEndSymbol(ch, outputController);
      case _SubParser.numberPart1:
        return _handleNumberAtNegative(ch, outputController);
      case _SubParser.numberPart2:
        return _handleNumberNoNegative(ch, outputController);
      case _SubParser.numberPart3:
        return _handleNumberExponent(ch, outputController);
      case _SubParser.numberPart4:
        return _handleNumberExponentInitialDigit(ch, outputController);
      case _SubParser.string:
        return _handleString(ch, outputController);
      case _SubParser.rawToken:
        return _handleNextSymbol(ch, outputController);
      case _SubParser.errored:
        break;
    }
  }

  void _handleBeginSymbol(int ch, StreamController outputController) {
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

      outputController.add(_addJsonStreamingEvent(JsonStreamingBox.object,
          _currentPath, _currentContext, JsonStreamingEventType.open));
      _subParser = _SubParser.top;
      _weAreInObject = true;
      _requireKey = true;
      return;
    } else {
      try {
        _parserAssertNotReached("Expected {", outputController);
      } catch (err) {
        outputController.addError(err);
        _subParser = _SubParser.errored;
      }
    }
  }

  void _handleEndSymbol(int ch, StreamController outputController) {
    if (_isWhitespace(ch)) return;
    else {
      outputController.addError(new StateError("Expected WHITESPACE"));
      _subParser = _SubParser.errored;
    }
  }

  void _handleTopSymbol(int ch, StreamController outputController) {
    if (_isWhitespace(ch)) return;
    if (_weAreInImplicitArray) {
      outputController.addError(new StateError("Expected WHITESPACE or { "));
      _subParser = _SubParser.errored;
    } else if (_weAreInObject && (_requireComma || _requireKey) && ch == 125) {
      //Close brace }
      outputController.add(_addJsonStreamingEvent(JsonStreamingBox.object,
          _currentPath, _currentContext, JsonStreamingEventType.close));
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
      _parserAssertNotReached("Expected } or ,", outputController);
      _subParser = _SubParser.errored;
    } else if (_weAreInObject && _requireColon && ch == 58) {
      _requireColon = false;
      return;
    } else if (_weAreInObject && _requireColon) {
      _parserAssertNotReached("Expected :", outputController);
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
        outputController.addError(err);
        _subParser = _SubParser.errored;
      });
      return;
    } else if (_weAreInObject && _requireKey) {
      _parserAssertNotReached("Expected \" or }", outputController);
      _subParser = _SubParser.errored;
      return;
    } else if (_weAreInArray && ch == 93) {
      //Close bracket ]
      outputController.add(_addJsonStreamingEvent(JsonStreamingBox.array,
          _currentPath, _currentContext, JsonStreamingEventType.close));
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
      _parserAssertNotReached("Expected ] or ,", outputController);
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
      outputController.add(_addJsonStreamingEvent(JsonStreamingBox.object,
          _currentPath, _currentContext, JsonStreamingEventType.open));
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
      outputController.add(_addJsonStreamingEvent(JsonStreamingBox.array,
          _currentPath, _currentContext, JsonStreamingEventType.open));
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

        outputController.add(_makeFinalSymbol(_lastValueString));

        _subParser = _SubParser.top;
      }, onError: (error) {
        outputController.addError(error);
        _subParser = _SubParser.errored;
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
        outputController.add(_makeFinalSymbol(true));
        _subParser = _SubParser.top;
        _rawTokenResult = null;
      }).catchError((error) {
        outputController.addError(error);
        _subParser = _SubParser.errored;
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
        outputController.add(_makeFinalSymbol(false));

        _subParser = _SubParser.top;
        _rawTokenResult = null;
      }).catchError((error) {
        outputController.addError(error);
        _subParser = _SubParser.errored;
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
        outputController.add(_makeFinalSymbol(null));

        _subParser = _SubParser.top;
        _rawTokenResult = null;
      }).catchError((error) {
        outputController.addError(error);
        _subParser = _SubParser.errored;
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
        outputController.add(_makeFinalSymbol(result));
      }).catchError((error) {
        outputController.addError(error);
        _subParser = _SubParser.errored;
      });
      return;
    } else {
      _parserAssertNotReached(
          "Expected {, [, \", -, DIGIT, WHITESPACE, null, true, or false",
          outputController);
    }
  }

  void _handleNumberAtNegative(
      ch, StreamController<JsonStreamingEvent> outputController) {
    if (<int>[48, 49, 50, 51, 52, 53, 54, 55, 56, 57].contains(ch)) {
      _numberResult.writeCharCode(ch);
    } else {
      try {
        _parserAssertNotReachedSync("DIGIT");
      } catch (err) {
        _numberIsReady.completeError(err);
      }
    }
    _hasHadDecimal = false;
    _hasHadExponent = false;
    _subParser = _SubParser.numberPart2;
  }

  _handleNumberNoNegative(
      ch, StreamController<JsonStreamingEvent> outputController) {
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
      _handleTopSymbol(ch, outputController);
    } else if (!_hasHadDecimal && ch == 46) {
      _numberResult.writeCharCode(ch);
      _hasHadDecimal = true;
    } else if (ch == 46) {
      try {
        if (!_hasHadExponent) {
          _parserAssertNotReachedSync('Expected digit or e');
        } else {
          _parserAssertNotReachedSync('Expected digit');
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
        _parserAssertNotReachedSync('Expected digit');
      } catch (err) {
        _numberIsReady.completeError(err);
      }
    } else if (<int>[48, 49, 50, 51, 52, 53, 54, 55, 56, 57].contains(ch)) {
      _numberResult.writeCharCode(ch);
    } else {
      try {
        _parserAssertNotReachedSync("Expected NUMBER PART");
      } catch (err) {
        _numberIsReady.completeError(err);
      }
    }
  }

  _handleNumberExponent(
      ch, StreamController<JsonStreamingEvent> outputController) {
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
        _parserAssertNotReachedSync("Expected DIGIT, +, or -");
      } catch (err) {
        _numberIsReady.completeError(err);
      }
    }
  }

  _handleNumberExponentInitialDigit(
      ch, StreamController<JsonStreamingEvent> outputController) {
    if (<int>[48, 49, 50, 51, 52, 53, 54, 55, 56, 57].contains(ch)) {
      _numberResult.writeCharCode(ch);
      _hasHadExponent = true;
      _hasHadDecimal = true;
      _subParser = _SubParser.numberPart2;
    } else {
      try {
        _parserAssertNotReached("Expected DIGIT", outputController);
      } catch (err) {
        _numberIsReady.completeError(err);
      }
    }
  }

  JsonStreamingEvent _addJsonStreamingEvent(
          JsonStreamingBox object,
          List currentPath,
          Object currentContext,
          JsonStreamingEventType eventType) =>
      new JsonStreamingEvent(object, currentPath, currentContext, eventType);

  void _parserAssertNotReached(
      String message, StreamController<JsonStreamingEvent> outputController) {
    outputController.addError(new StateError(message));
    _subParser = _SubParser.errored;
  }

  void _parserAssertNotReachedSync(String message) {
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
    var result = _addJsonStreamingEvent(
        JsonStreamingBox.na, _currentPath, value, JsonStreamingEventType.token);
    _currentPath.removeLast();
    _requireComma = true;
    return result;
  }

  bool _parserAssert(bool condition, String message) {
    if (!condition) {
      _parserAssertNotReachedSync(message);
      return true;
    }
    return false;
  }

  void _handleNextSymbol(int ch, StreamController outputController) =>
      _rawTokenResult.complete(ch);

  void _handleStringEof(Completer stringIsReady) =>
      stringIsReady.completeError(new StateError('Expected " but found EOF'));

  void _handleString(ch, StreamController outputController) {
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
                outputController.addError(error);
                _subParser = _SubParser.errored;
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
}
