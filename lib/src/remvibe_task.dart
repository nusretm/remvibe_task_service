part of 'remvibe_task_service.dart';

typedef RemVibeTaskExecuteCallback = FutureOr<void> Function(
  RemVibeTaskList taskList,
  RemVibeTask task,
);

typedef RemVibeTaskCancelCallback = FutureOr<void> Function(
  RemVibeTaskList taskList,
  RemVibeTask task,
);

class RemVibeTask {
  RemVibeTask({
    required this.title,
    required this.onExecute,
    this.onCancel,
  }) {
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'Must not be empty.');
    }
  }

  final String title;
  final RemVibeTaskExecuteCallback onExecute;
  final RemVibeTaskCancelCallback? onCancel;

  RemVibeTaskList? _taskList;
  RemVibeTaskStatus _status = RemVibeTaskStatus.idle;
  String _statusText = '';
  int _percent = 0;

  RemVibeTaskStatus get status => _status;

  String get statusText => _statusText;

  set statusText(String value) => _setStatusText(value);

  int get percent => _percent;

  set percent(int value) => _setPercent(value);

  bool get _isTerminal =>
      _status == RemVibeTaskStatus.completed ||
      _status == RemVibeTaskStatus.cancelled ||
      _status == RemVibeTaskStatus.error;

  void complete([String? statusText]) {
    _completeTerminal(
      RemVibeTaskStatus.completed,
      statusText: statusText,
      forcePercent: 100,
    );
  }

  void error([String? statusText]) {
    _completeTerminal(
      RemVibeTaskStatus.error,
      statusText: statusText,
    );
  }

  void cancel([String? statusText]) {
    _completeTerminal(
      RemVibeTaskStatus.cancelled,
      statusText: statusText,
    );
  }

  void _attach(RemVibeTaskList taskList) {
    final RemVibeTaskList? owner = _taskList;
    if (owner != null && !identical(owner, taskList)) {
      throw StateError('RemVibeTask cannot belong to more than one TaskList.');
    }

    _setTaskList(taskList);
  }

  void _run(RemVibeTaskList taskList) {
    if (_status != RemVibeTaskStatus.idle) {
      return;
    }

    _setStatus(RemVibeTaskStatus.executing);

    unawaited(
      Future<void>.sync(() => onExecute(taskList, this)).catchError(
        (Object error, StackTrace _) {
          _failRuntime(error);
        },
      ),
    );
  }

  Future<void> _requestCancel(
    RemVibeTaskList taskList, [
    String? statusText,
  ]) {
    if (_isTerminal) {
      return Future<void>.value();
    }

    final RemVibeTaskCancelCallback? callback = onCancel;
    if (callback == null) {
      cancel(statusText);
      return Future<void>.value();
    }

    return Future<void>.sync(() => callback(taskList, this)).then<void>(
      (_) {
        if (!_isTerminal) {
          cancel(statusText);
        }
      },
      onError: (Object error, StackTrace _) {
        _failRuntime(error);
      },
    );
  }

  void _cancelPending([String? statusText]) {
    if (_status != RemVibeTaskStatus.idle) {
      return;
    }

    if (statusText != null) {
      _setStatusText(statusText);
    }
    _setStatus(RemVibeTaskStatus.cancelled);
  }

  void _failRuntime(Object runtimeError) {
    if (_isTerminal) {
      return;
    }

    if (_status == RemVibeTaskStatus.idle) {
      _setStatus(RemVibeTaskStatus.executing);
    }
    error(runtimeError.toString());
  }

  void _completeTerminal(
    RemVibeTaskStatus newStatus, {
    String? statusText,
    int? forcePercent,
  }) {
    if (_isTerminal) {
      return;
    }
    if (_status != RemVibeTaskStatus.executing) {
      throw StateError('RemVibeTask can only finish while executing.');
    }

    if (statusText != null) {
      _setStatusText(statusText);
    }
    if (forcePercent != null) {
      _setPercent(forcePercent);
    }
    _setStatus(newStatus);

    final RemVibeTaskList? taskList = _taskList;
    if (taskList == null) {
      return;
    }

    if (newStatus == RemVibeTaskStatus.completed) {
      taskList._taskCompleted(this);
      return;
    }
    if (newStatus == RemVibeTaskStatus.error) {
      taskList._taskError(this);
      return;
    }
    if (newStatus == RemVibeTaskStatus.cancelled) {
      taskList._taskCancelled(this);
      return;
    }

    throw StateError('Expected a terminal RemVibeTaskStatus.');
  }

  void _setTaskList(RemVibeTaskList taskList) {
    _taskList = taskList;
  }

  void _setStatus(RemVibeTaskStatus newStatus) {
    if (_status == newStatus) {
      return;
    }

    _status = newStatus;
    _notifyTaskList();
  }

  void _setStatusText(String value) {
    if (_isTerminal || _statusText == value) {
      return;
    }

    _statusText = value;
    final RemVibeTaskList? taskList = _taskList;
    if (taskList == null) {
      return;
    }

    taskList._taskStatusTextChanged(this, value);
  }

  void _setPercent(int value) {
    if (value < 0 || value > 100) {
      throw ArgumentError.value(value, 'value', 'Must be between 0 and 100.');
    }
    if (_isTerminal || _percent == value) {
      return;
    }

    _percent = value;
    _notifyTaskList();
  }

  void _notifyTaskList() {
    _taskList?._notifyStatus();
  }
}
