from pathlib import Path

path = Path('apps/mobile/lib/screens/events_module_screen.dart')
text = path.read_text(encoding='utf-8')

replacements = {
    "if (value != null) setDialogState(() => severity = value);": "if (value != null) {\n                              setDialogState(() => severity = value);\n                            }",
    "if (value != null) setDialogState(() => status = value);": "if (value != null) {\n                              setDialogState(() => status = value);\n                            }",
}
for old, new in replacements.items():
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'expected exactly one match for lint fix, found {count}: {old}')
    text = text.replace(old, new, 1)

start = text.find('class _OperationSection extends StatelessWidget {')
end = text.find('class _SimpleFutureList extends StatelessWidget {', start)
if start == -1 or end == -1:
    raise SystemExit('could not locate legacy _OperationSection block')
text = text[:start] + text[end:]

start = text.find('Future<bool> _textDialog(')
end = text.find('IconData _eventIcon(', start)
if start == -1 or end == -1:
    raise SystemExit('could not locate legacy _textDialog block')
text = text[:start] + text[end:]

path.write_text(text, encoding='utf-8')
