import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('kangoshiShareText')
external JSPromise<JSString> _shareText(JSString value);
@JS('kangoshiSharePng')
external JSPromise<JSString> _sharePng(JSString base64);

Future<String> shareResultText(String value) async =>
    (await _shareText(value.toJS).toDart).toDart;

Future<String> shareResultPng(Uint8List bytes) async =>
    (await _sharePng(base64Encode(bytes).toJS).toDart).toDart;
