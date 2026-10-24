import 'package:flutter/material.dart';

import '../models/vehicle_log.dart';
import 'theme.dart';

class ChannelEdit {
  const ChannelEdit({required this.order, required this.aliases});

  final List<int> order;
  final Map<int, String> aliases;
}

/// Rename and reorder the channels that are currently on the chart.
///
/// Units are never edited here: they belong to the log file.
Future<ChannelEdit?> showChannelEditor(
  BuildContext context, {
  required VehicleLog log,
  required List<int> order,
  required Map<int, String> aliases,
}) {
  return showDialog<ChannelEdit>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _ChannelEditorDialog(
      log: log,
      order: order,
      aliases: aliases,
    ),
  );
}

class _ChannelEditorDialog extends StatefulWidget {
  const _ChannelEditorDialog({
    required this.log,
    required this.order,
    required this.aliases,
  });

  final VehicleLog log;
  final List<int> order;
  final Map<int, String> aliases;

  @override
  State<_ChannelEditorDialog> createState() => _ChannelEditorDialogState();
}

class _ChannelEditorDialogState extends State<_ChannelEditorDialog> {
  late List<int> _order;
  late Map<int, TextEditingController> _names;

  @override
  void initState() {
    super.initState();
    _order = List<int>.from(widget.order);
    _names = <int, TextEditingController>{};
    for (final index in _order) {
      _names[index] = TextEditingController(
        text: widget.aliases[index] ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _names.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _move(int from, int delta) {
    final to = from + delta;
    if (to < 0 || to >= _order.length) return;
    setState(() {
      final item = _order.removeAt(from);
      _order.insert(to, item);
    });
  }

  void _save() {
    final aliases = <int, String>{};
    for (final index in _order) {
      final name = _names[index]?.text.trim() ?? '';
      if (name.isNotEmpty && name != widget.log.channels[index].name) {
        aliases[index] = name;
      }
    }
    Navigator.of(context).pop(ChannelEdit(order: _order, aliases: aliases));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return AlertDialog(
      backgroundColor: kSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      title: Row(
        children: [
          const Icon(Icons.tune, size: 18, color: kAccent),
          const SizedBox(width: 10),
          const Text(
            'Edit chart channels',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            '${_order.length}',
            style: const TextStyle(fontSize: 11, color: kMuted),
          ),
          if (keyboard > 0)
            IconButton(
              onPressed: () => FocusScope.of(context).unfocus(),
              icon: const Icon(Icons.keyboard_hide, size: 18),
              color: kAccent,
              visualDensity: VisualDensity.compact,
              tooltip: 'Hide keyboard',
            ),
        ],
      ),
      content: SizedBox(
        width: media.width < 620 ? media.width * 0.86 : 560,
        height: (media.height - keyboard - 96).clamp(150.0, 430.0),
        child: _order.isEmpty
            ? const Center(
                child: Text(
                  'No channels on the chart yet',
                  style: TextStyle(color: kMuted, fontSize: 12),
                ),
              )
            : ListView.separated(
                itemCount: _order.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: kBorder),
                itemBuilder: (context, position) {
                  final index = _order[position];
                  final channel = widget.log.channels[index];
                  final colour = kTraceColors[position % kTraceColors.length];

                  return Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Center(
                          child: Container(
                            width: 3,
                            height: 22,
                            decoration: BoxDecoration(
                              color: colour,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _names[index],
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                          ),
                          cursorColor: kAccent,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) =>
                              FocusScope.of(context).unfocus(),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: channel.name,
                            hintStyle: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF5A6779),
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          channel.unit.isEmpty ? '—' : channel.unit,
                          style: const TextStyle(fontSize: 11, color: kMuted),
                        ),
                      ),
                      IconButton(
                        onPressed: position == 0
                            ? null
                            : () => _move(position, -1),
                        icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                        color: kMuted,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Move up',
                      ),
                      IconButton(
                        onPressed: position == _order.length - 1
                            ? null
                            : () => _move(position, 1),
                        icon:
                            const Icon(Icons.keyboard_arrow_down, size: 18),
                        color: kMuted,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Move down',
                      ),
                    ],
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: kMuted, fontSize: 12.5),
          ),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: kAccent,
            foregroundColor: const Color(0xFF04121F),
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
