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

  test('service is singleton and name lookup returns the effective TaskList',
      () async {
    expect(identical(RemVibeTaskService(), RemVibeTaskService()), isTrue);

    final Completer<void> taskStarted = Completer<void>();
    final Completer<void> listCompleted = Completer<void>();
    late RemVibeTask task;

    final RemVibeTaskList original = RemVibeTaskList(
      title: 'Minecraft 26.1.2',
      name: 'mc-26.1.2',
      tag: 'minecraft',
      onPrepare: (RemVibeTaskList taskList) {
        task = RemVibeTask(
          title: 'Hold queue',
          onExecute: (RemVibeTaskList taskList, RemVibeTask task) {
            taskStarted.complete();
          },
        );
        taskList.add(task);
      },
      onStatus: (RemVibeTaskList taskList) {
        if (taskList.status == RemVibeTaskListStatus.completed &&
            !listCompleted.isCompleted) {
          listCompleted.complete();
        }
      },
    );

    final RemVibeTaskList effective = service.add(original);
    await taskStarted.future;

    final RemVibeTaskList duplicate = RemVibeTaskList(
      title: 'Duplicate',
      name: 'mc-26.1.2',
      tag: 'minecraft',
      onPrepare: (RemVibeTaskList taskList) {},
    );

    expect(identical(effective, original), isTrue);
    expect(identical(service.add(duplicate), original), isTrue);
    expect(identical(service.getFromName('mc-26.1.2'), original), isTrue);

    task.complete();
    await listCompleted.future.timeout(const Duration(seconds: 1));

    expect(service.getFromName('mc-26.1.2'), isNull);
  });

  test('prepare runs only when TaskList reaches the front of the queue',
      () async {
    final Completer<void> firstStarted = Completer<void>();
    final Completer<void> releaseFirst = Completer<void>();
    final Completer<void> secondCompleted = Completer<void>();

    var assetReady = false;
    var secondPrepared = false;
    var redundantAssetTaskCreated = false;

    final RemVibeTaskList first = RemVibeTaskList(
      title: 'First install',
      name: 'first-install',
      tag: 'minecraft',
      onPrepare: (RemVibeTaskList taskList) {
        taskList.add(
          RemVibeTask(
            title: 'Download shared asset',
            onExecute: (
              RemVibeTaskList taskList,
              RemVibeTask task,
            ) async {
              firstStarted.complete();
              await releaseFirst.future;
              assetReady = true;
              task.complete();
            },
          ),
        );
      },
    );

    final RemVibeTaskList second = RemVibeTaskList(
      title: 'Second install',
      name: 'second-install',
      tag: 'minecraft',
      onPrepare: (RemVibeTaskList taskList) {
        secondPrepared = true;
        if (!assetReady) {
          redundantAssetTaskCreated = true;
          taskList.add(
            RemVibeTask(
              title: 'Redundant asset',
              onExecute: (
                RemVibeTaskList taskList,
                RemVibeTask task,
              ) {
                task.complete();
              },
            ),
          );
        }
      },
      onStatus: (RemVibeTaskList taskList) {
        if (taskList.status == RemVibeTaskListStatus.completed &&
            !secondCompleted.isCompleted) {
          secondCompleted.complete();
        }
      },
    );

    service.add(first);
    service.add(second);

    await firstStarted.future;
    expect(secondPrepared, isFalse);

    releaseFirst.complete();
    await secondCompleted.future.timeout(const Duration(seconds: 1));

    expect(secondPrepared, isTrue);
    expect(redundantAssetTaskCreated, isFalse);
    expect(second.items, isEmpty);
    expect(second.percent, 100);
  });

  test('returning from onExecute does not complete the Task', () async {
    final Completer<void> firstStarted = Completer<void>();
    final Completer<void> listCompleted = Completer<void>();
    var secondStarted = false;
    late RemVibeTask firstTask;

    final RemVibeTaskList taskList = RemVibeTaskList(
      title: 'Sequential work',
      name: 'sequential-work',
      tag: 'test',
      onPrepare: (RemVibeTaskList taskList) {
        firstTask = RemVibeTask(
          title: 'First',
          onExecute: (RemVibeTaskList taskList, RemVibeTask task) {
            firstStarted.complete();
          },
        );
        taskList.add(firstTask);
        taskList.add(
          RemVibeTask(
            title: 'Second',
            onExecute: (RemVibeTaskList taskList, RemVibeTask task) {
              secondStarted = true;
              task.complete();
            },
          ),
        );
      },
      onStatus: (RemVibeTaskList taskList) {
        if (taskList.status == RemVibeTaskListStatus.completed &&
            !listCompleted.isCompleted) {
          listCompleted.complete();
        }
      },
    );

    service.add(taskList);
    await firstStarted.future;
    await Future<void>.delayed(Duration.zero);

    expect(firstTask.status, RemVibeTaskStatus.executing);
    expect(secondStarted, isFalse);

    firstTask.complete();
    await listCompleted.future.timeout(const Duration(seconds: 1));

    expect(secondStarted, isTrue);
  });

  test('Task percent contributes naturally to TaskList percent', () async {
    final Completer<void> thirdStarted = Completer<void>();
    final Completer<void> listCompleted = Completer<void>();
    var statusNotifications = 0;
    late RemVibeTask thirdTask;

    final RemVibeTaskList taskList = RemVibeTaskList(
      title: 'Progress',
      name: 'progress',
      tag: 'test',
      onPrepare: (RemVibeTaskList taskList) {
        for (var index = 0; index < 5; index++) {
          if (index == 2) {
            thirdTask = RemVibeTask(
              title: 'Third',
              onExecute: (RemVibeTaskList taskList, RemVibeTask task) {
                task.statusText = 'İndiriliyor...';
                task.percent = 43;
                thirdStarted.complete();
              },
            );
            taskList.add(thirdTask);
          } else {
            taskList.add(
              RemVibeTask(
                title: 'Task $index',
                onExecute: (RemVibeTaskList taskList, RemVibeTask task) {
                  task.complete();
                },
              ),
            );
          }
        }
      },
      onStatus: (RemVibeTaskList taskList) {
        statusNotifications++;
        if (taskList.status == RemVibeTaskListStatus.completed &&
            !listCompleted.isCompleted) {
          listCompleted.complete();
        }
      },
    );

    service.add(taskList);
    await thirdStarted.future;

    expect(taskList.completedCount, 2);
    expect(taskList.totalCount, 5);
    expect(taskList.percent, 48);
    expect(identical(taskList.currentTask, thirdTask), isTrue);
    expect(identical(service.currentTask, thirdTask), isTrue);
    expect(thirdTask.percent, 43);
    expect(thirdTask.statusText, 'İndiriliyor...');
    expect(taskList.statusText, 'İndiriliyor...');
    expect(statusNotifications, greaterThan(0));

    thirdTask.complete();
    await listCompleted.future.timeout(const Duration(seconds: 1));

    expect(taskList.completedCount, 5);
    expect(taskList.percent, 100);
  });

  test('service cancellation invokes current Task onCancel', () async {
    final Completer<void> taskStarted = Completer<void>();
    var cancelCalled = false;
    late RemVibeTask task;

    final RemVibeTaskList taskList = RemVibeTaskList(
      title: 'Cancelable work',
      name: 'cancelable-work',
      tag: 'test',
      onPrepare: (RemVibeTaskList taskList) {
        task = RemVibeTask(
          title: 'Cancelable task',
          onExecute: (RemVibeTaskList taskList, RemVibeTask task) {
            taskStarted.complete();
          },
          onCancel: (RemVibeTaskList taskList, RemVibeTask task) async {
            await Future<void>.delayed(const Duration(milliseconds: 1));
            cancelCalled = true;
          },
        );
        taskList.add(task);
      },
    );

    service.add(taskList);
    await taskStarted.future;

    await service.cancel(taskList, 'İşlem iptal edildi.');

    expect(cancelCalled, isTrue);
    expect(task.status, RemVibeTaskStatus.cancelled);
    expect(task.statusText, 'İşlem iptal edildi.');
    expect(taskList.status, RemVibeTaskListStatus.cancelled);
    expect(service.getFromName('cancelable-work'), isNull);
  });

  test('onExecute exception becomes Task and TaskList error', () async {
    final Completer<void> listFailed = Completer<void>();
    late RemVibeTask task;

    final RemVibeTaskList taskList = RemVibeTaskList(
      title: 'Failing work',
      name: 'failing-work',
      tag: 'test',
      onPrepare: (RemVibeTaskList taskList) {
        task = RemVibeTask(
          title: 'Fail',
          onExecute: (RemVibeTaskList taskList, RemVibeTask task) {
            throw StateError('execute failed');
          },
        );
        taskList.add(task);
      },
      onStatus: (RemVibeTaskList taskList) {
        if (taskList.status == RemVibeTaskListStatus.error &&
            !listFailed.isCompleted) {
          listFailed.complete();
        }
      },
    );

    service.add(taskList);
    await listFailed.future.timeout(const Duration(seconds: 1));

    expect(task.status, RemVibeTaskStatus.error);
    expect(task.statusText, contains('execute failed'));
    expect(taskList.status, RemVibeTaskListStatus.error);
    expect(identical(service.getFromName('failing-work'), taskList), isTrue);

    await service.cancel(taskList);
    expect(service.getFromName('failing-work'), isNull);
  });

  test('Task error cancels pending tasks and service advances', () async {
    final Completer<void> firstFailed = Completer<void>();
    final Completer<void> secondCompleted = Completer<void>();
    late RemVibeTask pendingTask;

    final RemVibeTaskList first = RemVibeTaskList(
      title: 'Failing list',
      name: 'failing-list-advance',
      tag: 'test',
      onPrepare: (RemVibeTaskList taskList) {
        taskList.add(
          RemVibeTask(
            title: 'Failing task',
            onExecute: (RemVibeTaskList taskList, RemVibeTask task) {
              task.error('boom');
            },
          ),
        );
        pendingTask = RemVibeTask(
          title: 'Must not run',
          onExecute: (RemVibeTaskList taskList, RemVibeTask task) {
            fail('Pending task must not execute after an error.');
          },
        );
        taskList.add(pendingTask);
      },
      onStatus: (RemVibeTaskList taskList) {
        if (taskList.status == RemVibeTaskListStatus.error &&
            !firstFailed.isCompleted) {
          firstFailed.complete();
        }
      },
    );

    final RemVibeTaskList second = RemVibeTaskList(
      title: 'Next list',
      name: 'next-list-after-error',
      tag: 'test',
      onPrepare: (RemVibeTaskList taskList) {
        taskList.add(
          RemVibeTask(
            title: 'Next task',
            onExecute: (RemVibeTaskList taskList, RemVibeTask task) {
              task.complete();
            },
          ),
        );
      },
      onStatus: (RemVibeTaskList taskList) {
        if (taskList.status == RemVibeTaskListStatus.completed &&
            !secondCompleted.isCompleted) {
          secondCompleted.complete();
        }
      },
    );

    service.add(first);
    service.add(second);

    await firstFailed.future.timeout(const Duration(seconds: 1));
    await secondCompleted.future.timeout(const Duration(seconds: 1));

    expect(first.status, RemVibeTaskListStatus.error);
    expect(first.statusText, 'boom');
    expect(pendingTask.status, RemVibeTaskStatus.cancelled);
    expect(identical(service.getFromName('failing-list-advance'), first), isTrue);
    expect(service.getFromName('next-list-after-error'), isNull);

    await service.cancel(first);
  });

  test('empty prepare completes without entering running state', () async {
    final List<RemVibeTaskListStatus> statuses = <RemVibeTaskListStatus>[];
    final Completer<void> completed = Completer<void>();

    final RemVibeTaskList taskList = RemVibeTaskList(
      title: 'Already ready',
      name: 'already-ready',
      tag: 'minecraft',
      onPrepare: (RemVibeTaskList taskList) {},
      onStatus: (RemVibeTaskList taskList) {
        statuses.add(taskList.status);
        if (taskList.status == RemVibeTaskListStatus.completed &&
            !completed.isCompleted) {
          completed.complete();
        }
      },
    );

    service.add(taskList);
    await completed.future.timeout(const Duration(seconds: 1));

    expect(statuses, contains(RemVibeTaskListStatus.preparing));
    expect(statuses, isNot(contains(RemVibeTaskListStatus.running)));
    expect(taskList.items, isEmpty);
    expect(taskList.percent, 100);
  });
}
