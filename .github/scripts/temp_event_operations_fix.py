from pathlib import Path

path = Path('apps/mobile/lib/screens/events_module_screen.dart')
text = path.read_text()
old = """                            'completed_at': status == 'done'
                                ? task?['completed_at'] ??
                                    DateTime.now().toUtc().toIso8601String()
                                : null,
"""
new = """                            'completed_at': status == 'done'
                                ? (task == null
                                    ? DateTime.now().toUtc().toIso8601String()
                                    : task['completed_at'] ??
                                        DateTime.now().toUtc().toIso8601String())
                                : null,
"""
if old not in text:
    raise SystemExit('completed_at expression not found')
path.write_text(text.replace(old, new, 1))
