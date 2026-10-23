import 'package:flutter/material.dart';

import 'theme.dart';

class LandingView extends StatelessWidget {
  const LandingView({
    super.key,
    required this.busy,
    required this.error,
    required this.onOpen,
    required this.onSample,
  });

  final bool busy;
  final String? error;
  final VoidCallback onOpen;
  final VoidCallback onSample;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: kSurfaceAlt,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder),
                ),
                child: const Icon(Icons.show_chart, color: kAccent, size: 30),
              ),
              const SizedBox(height: 22),
              const Text(
                'Datalog Viewer',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Open an SCT LiveLink CSV log to explore it.\n'
                'Built for landscape, tuned for a phone.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: kMuted, height: 1.5),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: busy ? null : onOpen,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open, size: 18),
                  label: Text(busy ? 'Opening…' : 'Open datalog'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: const Color(0xFF04121F),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: busy ? null : onSample,
                child: const Text(
                  'Load sample log',
                  style: TextStyle(color: kMuted, fontSize: 12.5),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x22FF6B6B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x66FF6B6B)),
                  ),
                  child: Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFFFB4B4),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 26),
              const Text(
                'CSV · TSV · TXT',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: Color(0xFF44505F),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
