import 'package:flutter/services.dart';

Future<String> shareResultText(String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  return '共有テキストをコピーしました';
}

Future<String> shareResultPng(Uint8List bytes) async => '画像の保存はWeb版で利用できます';
