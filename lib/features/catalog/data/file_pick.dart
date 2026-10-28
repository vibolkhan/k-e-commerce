import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file the staff member chose, read into memory.
typedef PickedFile = ({String name, Uint8List bytes});

/// Opens the system file chooser for [extensions]; [multiple] allows more
/// than one file. An empty list when nothing was chosen.
typedef PickFiles =
    Future<List<PickedFile>> Function({
      required List<String> extensions,
      bool multiple,
    });

Future<List<PickedFile>> _pickWithFilePicker({
  required List<String> extensions,
  bool multiple = false,
}) async {
  final files = multiple
      ? await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: extensions,
        )
      : [
          ?await FilePicker.pickFile(
            type: FileType.custom,
            allowedExtensions: extensions,
          ),
        ];
  return [for (final f in files) (name: f.name, bytes: await f.readAsBytes())];
}

/// Tests override this to "choose" files without a dialog.
final pickFilesProvider = Provider<PickFiles>((ref) => _pickWithFilePicker);
