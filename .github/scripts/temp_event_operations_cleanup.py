from pathlib import Path

path = Path('apps/mobile/lib/screens/events_module_screen.dart')
text = path.read_text()

text = text.replace(
    """    required this.onAdd,
    this.onRowAction,
    this.actionLabel,
""",
    """    required this.onAdd,
""",
    1,
)
text = text.replace(
    """  final VoidCallback onAdd;
  final Future<void> Function(Map<String, dynamic>)? onRowAction;
  final String? actionLabel;
""",
    """  final VoidCallback onAdd;
""",
    1,
)
text = text.replace(
    """                trailing: onRowAction == null
                    ? null
                    : TextButton(
                        onPressed: () => onRowAction!(row),
                        child: Text(actionLabel ?? 'Abrir'),
                      ),
""",
    "",
    1,
)

start = text.find('Future<Map<String, dynamic>?> _pickMember(\n')
end = text.find('Future<bool> _textDialog(\n', start)
if start < 0 or end < 0:
    raise SystemExit('legacy _pickMember bounds not found')
text = text[:start] + text[end:]

path.write_text(text)
