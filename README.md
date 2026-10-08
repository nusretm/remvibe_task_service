# remvibe_task_service

Reusable Dart task-list queue and lifecycle service used by RemVibe projects.

## Features

- Application-wide singleton task service.
- Sequential TaskList execution.
- Explicit Task terminal lifecycle: complete, error, cancel.
- Progress and status-text propagation.
- TaskList add/update/remove observation.
- Shared `RemVibeClearPolicy` and `RemVibeListEventType` contracts from `remvibe_dart_models`.

## Usage

```dart
import 'package:remvibe_task_service/remvibe_task_service.dart';

final RemVibeTaskService service = RemVibeTaskService();

service.add(
  RemVibeTaskList(
    title: 'Example',
    name: 'example',
    tag: 'demo',
    onPrepare: (RemVibeTaskList list) {
      list.add(
        RemVibeTask(
          title: 'Run',
          onExecute: (RemVibeTaskList list, RemVibeTask task) {
            task.complete();
          },
        ),
      );
    },
  ),
);
```
