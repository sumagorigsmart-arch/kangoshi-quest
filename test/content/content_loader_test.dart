import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kangoshi_quest/content/content_loader.dart';

void main() {
  late String balance, titles;
  late Map<String, dynamic> fixture;
  setUp(() {
    balance = File('assets/content/balance_v1.json').readAsStringSync();
    titles = File('assets/content/titles_v1.json').readAsStringSync();
    fixture = jsonDecode(
      File('assets/content/fixture_events.json').readAsStringSync(),
    );
  });
  ContentException? invalid(void Function(Map<String, dynamic>) edit) {
    final data = jsonDecode(jsonEncode(fixture)) as Map<String, dynamic>;
    edit(data);
    try {
      ContentLoader.load(balance, titles, jsonEncode(data));
      return null;
    } on ContentException catch (e) {
      return e;
    }
  }

  test('fixture loads and models roundtrip', () {
    final b = ContentLoader.load(balance, titles, jsonEncode(fixture));
    expect(b.events.length, 3);
    expect(b.events.first.toJson()['eventId'], 'f01');
    expect(b.balance.slots.length, 22);
    expect(b.titles.length, 13);
  });
  test('duplicate event ID reports path and eventId', () {
    final e = invalid((m) {
      (m['events'] as List)[1]['eventId'] = 'f01';
    });
    expect(e, isNotNull);
    expect(e!.eventId, 'f01');
    expect(e.path, contains('events[1].eventId'));
  });
  test('unknown condition rejected', () {
    final e = invalid((m) {
      (m['events'] as List)[0]['conditions'] = [
        {'field': 'meters.unknown', 'op': 'gte', 'value': 100},
      ];
    });
    expect(e!.path, contains('conditions[0].field'));
    expect(e.eventId, 'f01');
  });
  test('negative task count and duration rejected', () {
    expect(
      invalid((m) {
        (m['events']
                as List)[0]['choices'][0]['outcomes'][0]['effects']['completeTasks']['record'] =
            -1;
      }),
      isNotNull,
    );
    expect(
      invalid((m) {
        (m['events']
                as List)[0]['choices'][0]['outcomes'][0]['effects']['durationMinutes'] =
            -1;
      }),
      isNotNull,
    );
  });
  test('break duration contradiction rejected', () {
    final e = invalid((m) {
      (m['events']
              as List)[1]['choices'][2]['outcomes'][0]['effects']['counters']['breakMinutes'] =
          6;
    });
    expect(e!.path, contains('effects'));
  });
  test('task minimum duration rejected', () {
    final e = invalid((m) {
      (m['events']
              as List)[0]['choices'][0]['outcomes'][0]['effects']['durationMinutes'] =
          41;
    });
    expect(e!.message, contains('Duration'));
  });
  test('record transfer rejected', () {
    final e = invalid((m) {
      (m['events']
          as List)[1]['choices'][0]['outcomes'][0]['effects']['transferTasks'] = {
        'record': 1,
      };
    });
    expect(e!.path, contains('transferTasks.record'));
  });
  test('approved transfer can use six-minute consultation without completion minimum', () {
    final data = jsonDecode(jsonEncode(fixture)) as Map<String, dynamic>;
    final effects =
        (data['events'] as List)[1]['choices'][0]['outcomes'][0]['effects']
            as Map<String, dynamic>;
    effects['durationMinutes'] = 6;
    effects['transferTasks'] = {'care': 1};
    expect(
      ContentLoader.load(balance, titles, jsonEncode(data)).events.length,
      3,
    );
  });
  test('unknown fields and nonfinite or zero weights rejected', () {
    expect(
      invalid((m) {
        (m['events'] as List)[0]['surprise'] = true;
      }),
      isNotNull,
    );
    expect(
      invalid((m) {
        (m['events'] as List)[0]['weight'] = 0;
      }),
      isNotNull,
    );
  });
  test('malformed JSON has root path and unknown eventId', () {
    expect(
      () => ContentLoader.load(balance, titles, '{'),
      throwsA(
        isA<ContentException>()
            .having((e) => e.path, 'path', 'events:\$')
            .having((e) => e.eventId, 'eventId', '<unknown>'),
      ),
    );
  });
}
