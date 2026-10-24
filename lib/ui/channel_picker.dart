import 'package:flutter/material.dart';

import '../models/vehicle_log.dart';
import 'theme.dart';

/// Full-width channel chooser: every channel with a check mark, in columns.
///
/// Returns the new ordered selection, or null when cancelled.
Future<List<int>?> showChannelPicker(
  BuildContext context, {
  required VehicleLog log,
  required List<int> picked,
}) {
  return showDialog<List<int>>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _ChannelPicker(
      log: log,
      picked: picked,
    ),
  );
}

class _ChannelPicker extends StatefulWidget {
  const _ChannelPicker({
    required this.log,
    required this.picked,
  });

  final VehicleLog log;
  final List<int> picked;

  @override
  State<_ChannelPicker> createState() => _ChannelPickerState();
}

class _ChannelPickerState extends State<_ChannelPicker> {
  late final Set<int> _selected;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = widget.picked.toSet();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<int> get _matches {
    final query = _search.text.trim().toLowerCase();
    final result = <int>[];
    for (var i = 0; i < widget.log.channels.length; i++) {
      final channel = widget.log.channels[i];
      if (query.isEmpty || channel.name.toLowerCase().contains(query)) {
        result.add(i);
      }
    }
    return result;
  }

  void _apply() {
    final ordered = <int>[
      for (final index in widget.picked)
        if (_selected.contains(index)) index,
      for (var i = 0; i < widget.log.channels.length; i++)
        if (_selected.contains(i) && !widget.picked.contains(i)) i,
    ];
    Navigator.of(context).pop(ordered);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final matches = _matches;
    final columns = media.width > 1100 ? 4 : (media.width > 760 ? 3 : 2);

    return Dialog(
      backgroundColor: kSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1180,
          maxHeight: media.height - keyboard - 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
              child: Row(
                children: [
                  const Text(
                    'Choose channels',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: kSurfaceAlt,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_selected.length} selected',
                      style: const TextStyle(fontSize: 11, color: kMuted),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text(
                      'Clear',
                      style: TextStyle(fontSize: 12, color: kMuted),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                    color: kMuted,
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                style: const TextStyle(fontSize: 13, color: Colors.white),
                cursorColor: kAccent,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: kSurfaceAlt,
                  hintText: 'Search ${widget.log.channels.length} channels',
                  hintStyle: const TextStyle(color: kMuted, fontSize: 12.5),
                  prefixIcon:
                      const Icon(Icons.search, size: 17, color: kMuted),
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: kBorder),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: 4.6,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 4,
                ),
                itemCount: matches.length,
                itemBuilder: (context, position) {
                  final index = matches[position];
                  final channel = widget.log.channels[index];
                  final checked = _selected.contains(index);
                  final unit = channel.unit;

                  return InkWell(
                    onTap: () => setState(() {
                      if (!_selected.remove(index)) _selected.add(index);
                    }),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: checked
                            ? const Color(0xFF1B2A3D)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            checked
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 19,
                            color: checked ? kAccent : kMuted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  channel.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: checked
                                        ? Colors.white
                                        : Colors.white70,
                                  ),
                                ),
                                if (unit.isNotEmpty)
                                  Text(
                                    unit,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      color: kMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, color: kBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: kMuted, fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selected.isEmpty ? null : _apply,
                    style: FilledButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: const Color(0xFF04121F),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text('Show ${_selected.length}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
