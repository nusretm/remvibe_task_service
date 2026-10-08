import 'dart:async';

import 'package:remvibe_task_service/remvibe_task_service.dart';
import 'package:test/test.dart';

void main() {
  final RemVibeTaskService service = RemVibeTaskService();

  setUp(() async {
    service.clearPolicy = RemVibeClearPolicy.immediate;
    service.clearCompletedItems();
    for (final RemVibeTaskList taskList
        in List<RemVibeTaskList>.of(service.items)) {
      await service.cancel(taskList);
    }
  });

  test('beforeNextAdd keeps completed results until the next batch starts',
      () async {
    service.clearPolicy = RemVibeClearPolicy.beforeNextAdd;
    final Completer<void> firstCompleted = Completer<void>();
    final RemVibeTaskList first = RemVibeTaskList(
      title: 'First',
      name: 'clear-policy-first',
      tag: 'test',
      onPrepare: (RemVibeTaskList list) {
        list.add(
          RemVibeTask(
            title: 'Complete',
            onExecute: (RemVibeTaskList list, RemVibeTask task) {
              task.complete('done');
            },
          ),
        );
      },
      onStatus: (RemVibeTaskList list) {
        if (list.status == RemVibeTaskListStatus.completed &&
            !firstCompleted.isCompleted) {
          firstCompleted.complete();
        }
      },
    );

    service.add(first);
    await firstCompleted.future.timeout(const Duration(seconds: 1));
    expect(service.getFromName(first.name), same(first));

    final Completer<void> secondStarted = Completer<void>();
    final RemVibeTaskList second = RemVibeTaskList(
      title: 'Second',
      name: 'clear-policy-second',
      tag: 'test',
      onPrepare: (RemVibeTaskList list) {
        list.add(
          RemVibeTask(
            title: 'Wait',
            onExecute: (RemVibeTaskList list, RemVibeTask task) {
              secondStarted.complete();
            },
          ),
        );
      },
    );

    service.add(second);
    await secondStarted.future.timeout(const Duration(seconds: 1));
    expect(service.getFromName(first.name), isNull);
    expect(service.getFromName(second.name), same(second));
    await service.cancel(second);
  });

  test('whenAllCompleted clears the completed batch together', () async {
    service.clearPolicy = RemVibeClearPolicy.whenAllCompleted;
    final Completer<void> firstStarted = Completer<void>();
    final Completer<void> releaseFirst = Completer<void>();
    final Completer<void> secondCompleted = Completer<void>();

    final RemVibeTaskList first = RemVibeTaskList(
      title: 'First',
      name: 'when-all-first',
      tag: 'test',
      onPrepare: (RemVibeTaskList list) {
        list.add(
          RemVibeTask(
            title: 'Wait',
            onExecute: (RemVibeTaskList list, RemVibeTask task) async {
              firstStarted.complete();
              await releaseFirst.future;
              task.complete();
            },
          ),
        );
      },
    );
    final RemVibeTaskList second = RemVibeTaskList(
      title: 'Second',
      name: 'when-all-second',
      tag: 'test',
      onPrepare: (RemVibeTaskList list) {
        list.add(
          RemVibeTask(
            title: 'Complete',
            onExecute: (RemVibeTaskList list, RemVibeTask task) {
              task.complete();
            },
          ),
        );
      },
      onStatus: (RemVibeTaskList list) {
        if (list.status == RemVibeTaskListStatus.completed &&
            !secondCompleted.isCompleted) {
          secondCompleted.complete();
        }
      },
    );

    service.add(first);
    service.add(second);
    await firstStarted.future.timeout(const Duration(seconds: 1));
    releaseFirst.complete();
    await secondCompleted.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);
    expect(service.items, isEmpty);
  });

  test('manual replaces a terminal TaskList with the same name', () async {
    service.clearPolicy = RemVibeClearPolicy.manual;
    final Completer<void> firstCompleted = Completer<void>();
    final RemVibeTaskList first = RemVibeTaskList(
      title: 'Old',
      name: 'manual-replace',
      tag: 'test',
      onPrepare: (RemVibeTaskList list) {
        list.add(
          RemVibeTask(
            title: 'Complete',
            onExecute: (RemVibeTaskList list, RemVibeTask task) {
              task.complete();
            },
          ),
        );
      },
      onStatus: (RemVibeTaskList list) {
        if (list.status == RemVibeTaskListStatus.completed &&
            !firstCompleted.isCompleted) {
          firstCompleted.complete();
        }
      },
    );

    service.add(first);
    await firstCompleted.future.timeout(const Duration(seconds: 1));

    final Completer<void> replacementStarted = Completer<void>();
    final RemVibeTaskList replacement = RemVibeTaskList(
      title: 'New',
      name: 'manual-replace',
      tag: 'test',
      onPrepare: (RemVibeTaskList list) {
        list.add(
          RemVibeTask(
            title: 'Wait',
            onExecute: (RemVibeTaskList list, RemVibeTask task) {
              replacementStarted.complete();
            },
          ),
        );
      },
    );

    expect(service.add(replacement), same(replacement));
    await replacementStarted.future.timeout(const Duration(seconds: 1));
    expect(service.getFromName('manual-replace'), same(replacement));
    expect(service.items, isNot(contains(first)));
    await service.cancel(replacement);
  });
}
