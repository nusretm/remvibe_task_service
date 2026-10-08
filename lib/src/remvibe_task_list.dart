part of 'remvibe_task_service.dart';

typedef RemVibeTaskListPrepareCallback = FutureOr<void> Function(
  RemVibeTaskList taskList,
);

typedef RemVibeTaskListStatusCallback = void Function(
  RemVibeTaskList taskList,
);

class RemVibeTaskList {
  RemVibeTaskList({
    required this.title,
    required this.name,
    required this.tag,
    required this.onPrepare,
    this.onStatus,
  }) {
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'Must not be empty.');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }
    if (tag.trim().isEmpty) {
      throw ArgumentError.value(tag, 'tag', 'Must not be empty.');
    }
  }

  final String title;
  final String name;
  final String tag;
  final RemVibeTaskListPrepareCallback onPrepare;
  final RemVibeTaskListStatusCallback? onStatus;

  final List<RemVibeTask> _items = <RemVibeTask>[];

  RemVibeTaskService? _service;
  RemVibeTaskListStatus _status = RemVibeTaskListStatus.idle;
  RemVibeTask? _currentTask;
  int _nextTaskIndex = 0;

  String statusText = '';

  List<RemVibeTask> get items => List<RemVibeTask>.unmodifiable(_items);

  RemVibeTaskListStatus get status => _status;

  RemVibeTask? get currentTask => _currentTask;

  int get completedCount => _items
      .where((RemVibeTask task) => task.status == RemVibeTaskStatus.completed)
      .length;

  int get totalCount => _items.length;

  int get percent {
    if (_items.isEmpty) {
      return _status == RemVibeTaskListStatus.completed ? 100 : 0;
    }

    final int total = _items.fold<int>(
      0,
      (int value, RemVibeTask task) => value + task.percent,
    );
    return (total / _items.length).floor();
  }

  bool get _isTerminal =>
      _status == RemVibeTaskListStatus.completed ||
      _status == RemVibeTaskListStatus.cancelled ||
      _status == RemVibeTaskListStatus.error;

  void add(RemVibeTask task) {
    if (_status != RemVibeTaskListStatus.preparing) {
      throw StateError(
        'RemVibeTaskList.add() is only available while preparing.',
      );
    }
    if (_items.contains(task)) {
      throw StateError('The same RemVibeTask cannot be added twice.');
    }

    task._attach(this);
    _items.add(task);
    _notifyStatus();
  }

  void _attach(RemVibeTaskService service) {
    final RemVibeTaskService? owner = _service;
    if (owner != null && !identical(owner, service)) {
      throw StateError(
        'RemVibeTaskList cannot belong to more than one TaskService.',
      );
    }

    _setService(service);
  }

  void _run() {
    if (_status != RemVibeTaskListStatus.idle) {
      return;
    }

    _setStatus(RemVibeTaskListStatus.preparing);

    unawaited(
      Future<void>.sync(() => onPrepare(this)).then<void>(
        (_) {
          if (_status != RemVibeTaskListStatus.preparing) {
            return;
          }

          if (_items.isEmpty) {
            _complete();
            return;
          }

          _setStatus(RemVibeTaskListStatus.running);
          _runNext();
        },
        onError: (Object error, StackTrace _) {
          if (_status == RemVibeTaskListStatus.preparing) {
            _failRuntime(error);
          }
        },
      ),
    );
  }

  void _runNext() {
    if (_status != RemVibeTaskListStatus.running || _currentTask != null) {
      return;
    }

    if (_nextTaskIndex >= _items.length) {
      _complete();
      return;
    }

    final RemVibeTask task = _items[_nextTaskIndex];
    _setCurrentTask(task);

    try {
      task._run(this);
    } catch (error) {
      task._failRuntime(error);
    }
  }

  void _taskCompleted(RemVibeTask task) {
    if (!identical(_currentTask, task)) {
      return;
    }

    _setCurrentTask(null);
    _setNextTaskIndex(_nextTaskIndex + 1);
    scheduleMicrotask(_runNext);
  }

  void _taskError(RemVibeTask task) {
    if (!identical(_currentTask, task)) {
      return;
    }

    _setCurrentTask(null);
    _setNextTaskIndex(_nextTaskIndex + 1);
    _cancelPendingTasks();
    _setStatus(RemVibeTaskListStatus.error);
    _service?._taskListError(this);
  }

  void _taskCancelled(RemVibeTask task) {
    if (!identical(_currentTask, task)) {
      return;
    }

    _setCurrentTask(null);
    _setNextTaskIndex(_nextTaskIndex + 1);
    _cancelPendingTasks();
    _setStatus(RemVibeTaskListStatus.cancelled);
    _service?._taskListCancelled(this);
  }

  void _taskStatusTextChanged(RemVibeTask task, String value) {
    if (identical(_currentTask, task)) {
      _setStatusText(value);
      return;
    }

    _notifyStatus();
  }

  Future<void> _requestCancel([String? statusText]) {
    if (_isTerminal) {
      return Future<void>.value();
    }

    final RemVibeTask? task = _currentTask;
    if (task != null) {
      return task._requestCancel(this, statusText);
    }

    _cancelPendingTasks(statusText);
    if (statusText != null) {
      _setStatusText(statusText);
    }
    _setStatus(RemVibeTaskListStatus.cancelled);
    _service?._taskListCancelled(this);
    return Future<void>.value();
  }

  void _complete() {
    if (_isTerminal) {
      return;
    }

    _setStatus(RemVibeTaskListStatus.completed);
    _service?._taskListCompleted(this);
  }

  void _failRuntime(Object runtimeError) {
    if (_isTerminal) {
      return;
    }

    _setCurrentTask(null);
    _cancelPendingTasks();
    _setStatusText(runtimeError.toString());
    _setStatus(RemVibeTaskListStatus.error);
    _service?._taskListError(this);
  }

  void _cancelPendingTasks([String? statusText]) {
    _items
        .skip(_nextTaskIndex)
        .where((RemVibeTask task) => task.status == RemVibeTaskStatus.idle)
        .forEach((RemVibeTask task) => task._cancelPending(statusText));
  }

  void _setService(RemVibeTaskService service) {
    _service = service;
  }

  void _setStatus(RemVibeTaskListStatus newStatus) {
    if (_status == newStatus) {
      return;
    }

    _status = newStatus;
    _notifyStatus();
  }

  void _setStatusText(String value) {
    if (statusText == value) {
      return;
    }

    statusText = value;
    _notifyStatus();
  }

  void _setCurrentTask(RemVibeTask? task) {
    if (identical(_currentTask, task)) {
      return;
    }

    _currentTask = task;

    if (task != null && statusText != task.statusText) {
      _setStatusText(task.statusText);
      return;
    }

    _notifyStatus();
  }

  void _setNextTaskIndex(int value) {
    _nextTaskIndex = value;
  }

  void _notifyStatus() {
    final RemVibeTaskListStatusCallback? callback = onStatus;
    if (callback != null) {
      try {
        callback(this);
      } catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }
    }

    _service?._taskListUpdated(this);
  }
}
