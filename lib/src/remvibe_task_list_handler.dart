part of 'remvibe_task_service.dart';

typedef RemVibeTaskListHandlerCallback = void Function(
  RemVibeTaskList list,
  RemVibeListEventType event,
);

class RemVibeTaskListHandler {
  RemVibeTaskListHandler({required this.onEvent}) {
    RemVibeTaskService()._registerHandler(this);
  }

  final RemVibeTaskListHandlerCallback onEvent;

  bool _active = false;
  bool _disposed = false;

  bool get active => _active;

  void start() {
    if (_disposed) {
      throw StateError('A disposed RemVibeTaskListHandler cannot be started.');
    }
    if (_active) {
      return;
    }

    _setActive(true);

    final List<RemVibeTaskList> lists = RemVibeTaskService().items;
    for (final RemVibeTaskList list in lists) {
      _emit(list, RemVibeListEventType.add);
    }
  }

  void stop() {
    if (_disposed) {
      return;
    }

    _setActive(false);
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _setActive(false);
    _disposed = true;
    RemVibeTaskService()._unregisterHandler(this);
  }

  void _setActive(bool value) {
    _active = value;
  }

  void _emit(RemVibeTaskList list, RemVibeListEventType event) {
    if (!_active || _disposed) {
      return;
    }

    try {
      onEvent(list, event);
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}
