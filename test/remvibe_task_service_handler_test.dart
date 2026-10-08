import 'dart:async';

import 'package:remvibe_task_service/remvibe_task_service.dart';
import 'package:test/test.dart';

void main() {
  final RemVibeTaskService service = RemVibeTaskService();

  setUp(() async {
    service.clearPolicy = RemVibeClearPolicy.immediate;
    service.clearCompletedItems();
    for (final RemVibeTaskList taskList in List<RemVibeTaskList>.of(service.items)) {
      await service.cancel(taskList);
    }
  });

  test('handler replays existing lists and observes add update remove events', () async {
    final List<(RemVibeTaskList, RemVibeListEventType)> events = <(RemVibeTaskList, RemVibeListEventType)>[];
    late RemVibeTask task;

    final RemVibeTaskListHandler handler = RemVibeTaskListHandler(
      onEvent: (RemVibeTaskList list, RemVibeListEventType event) {
        events.add((list, event));
      },
    );

    final RemVibeTaskList taskList = RemVibeTaskList(
      title: 'Observed list',
      name: 'handler-observed-list',
      tag: 'test',
      onPrepare: (RemVibeTaskList list) {
        task = RemVibeTask(
          title: 'Observed task',
          onExecute: (RemVibeTaskList list, RemVibeTask task) {},
        );
        list.add(task);
      },
    );

    service.add(taskList);
    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);

    handler.start();

    expect(events.length, 1);
    expect(identical(events.single.$1, taskList), isTrue);
    expect(events.single.$2, RemVibeListEventType.add);

    task.statusText = 'İndiriliyor...';
    task.percent = 43;

    expect(events.where((event) => event.$2 == RemVibeListEventType.update), isNotEmpty);
    expect(taskList.statusText, 'İndiriliyor...');
    expect(taskList.percent, 43);

    task.complete();
    await Future<void>.delayed(Duration.zero);

    expect(events.last.$2, RemVibeListEventType.remove);
    expect(identical(events.last.$1, taskList), isTrue);
    expect(service.getFromName('handler-observed-list'), isNull);

    handler.dispose();
  });

  test('handler stop suppresses events and start replays current lists', () async {
    final List<RemVibeListEventType> events = <RemVibeListEventType>[];
    late RemVibeTask task;

    final RemVibeTaskListHandler handler = RemVibeTaskListHandler(
      onEvent: (RemVibeTaskList list, RemVibeListEventType event) {
        events.add(event);
      },
    );

    handler.start();

    final RemVibeTaskList taskList = RemVibeTaskList(
      title: 'Stopped handler list',
      name: 'stopped-handler-list',
      tag: 'test',
      onPrepare: (RemVibeTaskList list) {
        task = RemVibeTask(
          title: 'Waiting task',
          onExecute: (RemVibeTaskList list, RemVibeTask task) {},
        );
        list.add(task);
      },
    );

    service.add(taskList);
    await Future<void>.delayed(Duration.zero);

    expect(events.first, RemVibeListEventType.add);
    expect(events, contains(RemVibeListEventType.update));

    events.clear();
    handler.stop();

    task.statusText = 'Sessiz update';
    task.percent = 25;

    expect(events, isEmpty);

    handler.start();

    expect(events, <RemVibeListEventType>[RemVibeListEventType.add]);

    events.clear();
    handler.dispose();

    task.percent = 50;

    expect(events, isEmpty);
    expect(() => handler.start(), throwsStateError);

    await service.cancel(taskList);
  });

  test('duplicate name does not emit another add event', () async {
    final List<RemVibeListEventType> events = <RemVibeListEventType>[];

    final RemVibeTaskListHandler handler = RemVibeTaskListHandler(
      onEvent: (RemVibeTaskList list, RemVibeListEventType event) {
        events.add(event);
      },
    )..start();

    final RemVibeTaskList original = RemVibeTaskList(
      title: 'Original',
      name: 'handler-duplicate-name',
      tag: 'test',
      onPrepare: (RemVibeTaskList list) {
        list.add(
          RemVibeTask(
            title: 'Waiting',
            onExecute: (RemVibeTaskList list, RemVibeTask task) {},
          ),
        );
      },
    );

    service.add(original);
    await Future<void>.delayed(Duration.zero);

    final int addCountBeforeDuplicate = events.where((event) => event == RemVibeListEventType.add).length;

    final RemVibeTaskList duplicate = RemVibeTaskList(
      title: 'Duplicate',
      name: 'handler-duplicate-name',
      tag: 'test',
      onPrepare: (RemVibeTaskList list) {},
    );

    expect(identical(service.add(duplicate), original), isTrue);
    expect(events.where((event) => event == RemVibeListEventType.add).length, addCountBeforeDuplicate);

    handler.dispose();
    await service.cancel(original);
  });

  test('removing retained error list emits remove', () async {
    final List<RemVibeListEventType> events = <RemVibeListEventType>[];
    final Completer<void> failed = Completer<void>();

    final RemVibeTaskListHandler handler = RemVibeTaskListHandler(
      onEvent: (RemVibeTaskList list, RemVibeListEventType event) {
        events.add(event);
      },
    )..start();

    final RemVibeTaskList taskList = RemVibeTaskList(
      title: 'Error list',
      name: 'handler-error-list',
      tag: 'test',
      onPrepare: (RemVibeTaskList list) {
        list.add(
          RemVibeTask(
            title: 'Failing task',
            onExecute: (RemVibeTaskList list, RemVibeTask task) {
              task.error('failed');
            },
          ),
        );
      },
      onStatus: (RemVibeTaskList list) {
        if (list.status == RemVibeTaskListStatus.error && !failed.isCompleted) {
          failed.complete();
        }
      },
    );

    service.add(taskList);
    await failed.future.timeout(const Duration(seconds: 1));

    expect(taskList.status, RemVibeTaskListStatus.error);
    expect(service.getFromName('handler-error-list'), same(taskList));
    expect(events, isNot(contains(RemVibeListEventType.remove)));

    await service.cancel(taskList);

    expect(events.last, RemVibeListEventType.remove);
    expect(service.getFromName('handler-error-list'), isNull);

    handler.dispose();
  });
}
