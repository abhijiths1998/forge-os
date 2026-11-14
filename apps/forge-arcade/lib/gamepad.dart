// A gamepad as the Arcade's remote: d-pad or left stick to move, A to play,
// B to quit. Flutter on Linux has no gamepad input, so this reads the kernel's
// joystick devices (/dev/input/js*) directly. Reading does not take the pad
// from a game: every reader gets every event.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

enum PadAction { left, right, up, down, select, back }

/// One js_event is 8 bytes: time u32, value s16, type u8, number u8.
/// Type 1 is a button, 2 an axis; 0x80 marks the initial state, which is
/// not a press. Returns null for anything that is not an action.
PadAction? parsePadEvent(List<int> bytes) {
  if (bytes.length < 8) return null;
  final d = ByteData.sublistView(Uint8List.fromList(bytes.sublist(0, 8)));
  final value = d.getInt16(4, Endian.little);
  final type = d.getUint8(6);
  final number = d.getUint8(7);
  if (type & 0x80 != 0) return null;
  if (type == 1 && value == 1) {
    return switch (number) {
      0 => PadAction.select, // A
      1 => PadAction.back, // B
      _ => null,
    };
  }
  if (type == 2 && value.abs() > 16000) {
    // Axes 0/1 are the left stick, 6/7 the d-pad on most pads.
    return switch (number) {
      0 || 6 => value < 0 ? PadAction.left : PadAction.right,
      1 || 7 => value < 0 ? PadAction.up : PadAction.down,
      _ => null,
    };
  }
  return null;
}

/// Actions from every connected pad. Quietly empty when there is none.
Stream<PadAction> padActions() {
  final controller = StreamController<PadAction>();
  final subs = <StreamSubscription<List<int>>>[];
  controller.onCancel = () {
    for (final s in subs) {
      s.cancel();
    }
  };
  try {
    final devices = Directory('/dev/input')
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'/js\d+$').hasMatch(f.path));
    for (final dev in devices) {
      // A js device delivers whole 8-byte events.
      subs.add(dev.openRead().listen((chunk) {
        for (var i = 0; i + 8 <= chunk.length; i += 8) {
          final a = parsePadEvent(chunk.sublist(i, i + 8));
          if (a != null) controller.add(a);
        }
      }, onError: (_) {}, cancelOnError: true));
    }
  } on FileSystemException {
    // No /dev/input to read.
  }
  return controller.stream;
}
