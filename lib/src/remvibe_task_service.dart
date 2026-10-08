library;

import 'dart:async';

import 'package:remvibe_dart_models/remvibe_dart_models.dart';

part 'remvibe_task.dart';
part 'remvibe_task_list.dart';
part 'remvibe_task_list_handler.dart';
part 'remvibe_task_list_status.dart';
part 'remvibe_task_status.dart';

class RemVibeTaskService {
  RemVibeTaskService._();

  static final RemVibeTaskService _instance = RemVibeTaskService._();

  factory RemVibeTaskService() => _instance;

  final List<RemVibeTaskList> _items = <RemVibeTaskList>[];
  final List<RemVibeTaskListHandler> _handlers = <RemVibeTaskListHandler>[];

  RemVibeClearPolicy clearPolicy = RemVibeClearPolicy.beforeNextAdd;
  RemVibeTaskList? _currentTaskList;

  List<RemVibeTaskList> get items => List<RemVibeTaskList>.unmodifiable(_items);

  RemVibeTaskList? get currentTaskList => _currentTaskList;

  RemVibeTask? get currentTask => _currentTaskList?.currentTask;

  RemVibeTaskList add(RemVibeTaskList taskList) {
    _applyClearPolicyBeforeAdd();

    final RemVibeTaskList? existing = getFromName(taskList.name);
    if (existing != null) {
      if (clearPolicy == RemVibeClearPolicy.manual && existing._isTerminal) {
        _removeTaskList(existing);
      } else {
        return existing;
      }
    }

    taskList._attach(this);
    _items.add(taskList);
    _emit(taskList, RemVibeListEventType.add);
    _runNext();
    return taskList;
  }

  RemVibeTaskList? getFromName(String name) {
    final int index = _items.indexWhere((RemVibeTaskList taskList) => taskList.name == name);
    return index < 0 ? null : _items[index];
  }

  void clearCompletedItems() {
    _clearCompletedItems();
  }

  Future<void> cancel(RemVibeTaskList taskList, [String? statusText]) {
    if (!_items.contains(taskList)) {
      return Future<void>.value();
    }

    if (taskList.status == RemVibeTaskListStatus.error) {
      _removeTaskList(taskList);
      _runNext();
      return Future<void>.value();
    }

    return taskList._requestCancel(statusText);
  }

  void _runNext() {
    if (_currentTaskList != null) {
      return;
    }

    final int index = _items.indexWhere((RemVibeTaskList taskList) => taskList.status == RemVibeTaskListStatus.idle);
    if (index < 0) {
      return;
    }

    final RemVibeTaskList taskList = _items[index];
    _setCurrentTaskList(taskList);

    try {
      taskList._run();
    } catch (error) {
      taskList._failRuntime(error);
    }
  }

  void _taskListCompleted(RemVibeTaskList taskList) {
    _releaseCurrentTaskList(taskList);

    if (clearPolicy == RemVibeClearPolicy.immediate) {
      _removeTaskList(taskList);
    } else if (clearPolicy == RemVibeClearPolicy.whenAllCompleted && _allItemsCompleted) {
      _clearCompletedItems();
    }

    scheduleMicrotask(_runNext);
  }

  void _taskListCancelled(RemVibeTaskList taskList) {
    _removeTaskList(taskList);
    _releaseCurrentTaskList(taskList);
    scheduleMicrotask(_runNext);
  }

  void _taskListError(RemVibeTaskList taskList) {
    _releaseCurrentTaskList(taskList);
    scheduleMicrotask(_runNext);
  }

  void _taskListUpdated(RemVibeTaskList taskList) {
    if (!_items.contains(taskList)) {
      return;
    }

    _emit(taskList, RemVibeListEventType.update);
  }

  void _registerHandler(RemVibeTaskListHandler handler) {
    if (_handlers.contains(handler)) {
      return;
    }

    _handlers.add(handler);
  }

  void _unregisterHandler(RemVibeTaskListHandler handler) {
    _handlers.remove(handler);
  }

  void _emit(RemVibeTaskList taskList, RemVibeListEventType event) {
    final List<RemVibeTaskListHandler> handlers = List<RemVibeTaskListHandler>.of(_handlers);
    for (final RemVibeTaskListHandler handler in handlers) {
      handler._emit(taskList, event);
    }
  }

  void _applyClearPolicyBeforeAdd() {
    if (clearPolicy == RemVibeClearPolicy.beforeNextAdd && _allItemsCompleted) {
      _clearCompletedItems();
    }
  }

  bool get _allItemsCompleted => _items.isNotEmpty && _items.every((RemVibeTaskList taskList) => taskList.status == RemVibeTaskListStatus.completed);

  void _clearCompletedItems() {
    final List<RemVibeTaskList> completed = _items.where((RemVibeTaskList taskList) => taskList.status == RemVibeTaskListStatus.completed).toList(growable: false);
    for (final RemVibeTaskList taskList in completed) {
      _removeTaskList(taskList);
    }
  }

  void _removeTaskList(RemVibeTaskList taskList) {
    if (!_items.remove(taskList)) {
      return;
    }

    _emit(taskList, RemVibeListEventType.remove);
    _releaseCurrentTaskList(taskList);
  }

  void _releaseCurrentTaskList(RemVibeTaskList taskList) {
    if (!identical(_currentTaskList, taskList)) {
      return;
    }

    _setCurrentTaskList(null);
  }

  void _setCurrentTaskList(RemVibeTaskList? taskList) {
    _currentTaskList = taskList;
  }
}
