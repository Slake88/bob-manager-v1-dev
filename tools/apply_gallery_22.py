from pathlib import Path

p = Path('apps/mobile/lib/screens/shop_screen.dart')
s = p.read_text(encoding='utf-8')

s = s.replace("import 'package:image_picker/image_picker.dart';\n", '')
marker = "import '../repositories/shop_repository.dart';\n"
gallery_import = "import '../widgets/product_image_gallery.dart';\n"
if gallery_import not in s:
    s = s.replace(marker, marker + gallery_import)

detail = s.find('class _ProductDetailScreenState')
start = s.find('  Future<void> _pickImage() async {', detail)
if start >= 0:
    end = s.find('  Future<void> _editVariant', start)
    if end < 0:
        raise SystemExit('Não foi encontrado o fim do método _pickImage antigo.')
    s = s[:start] + s[end:]

detail = s.find('class _ProductDetailScreenState')
target = "    final imageUrl = widget.repository.publicImageUrl(_product['photo_path']);\n"
pos = s.find(target, detail)
if pos >= 0:
    s = s[:pos] + s[pos + len(target):]

detail = s.find('class _ProductDetailScreenState')
body = s.find('body: ListView(', detail)
children = s.find('        children: [', body)
legacy_start = s.find('          AspectRatio(\n            aspectRatio: 16 / 7,', children)
legacy_end = s.find('          const SizedBox(height: 12),', legacy_start)
if legacy_start < 0 or legacy_end < 0:
    raise SystemExit('Não foi encontrado o bloco antigo da fotografia do artigo.')

gallery = """          ProductImageGallery(
            repository: widget.repository,
            productId: _product['id'].toString(),
            coverPath: _product['photo_path']?.toString(),
            canManage: _canManage,
            onChanged: _reloadProduct,
          ),
"""

s = s[:legacy_start] + gallery + s[legacy_end:]
p.write_text(s, encoding='utf-8')

# Remove o próprio patch para não ficar lixo no repositório.
Path(__file__).unlink()

print('Galeria 2.2 integrada na ficha do artigo com sucesso.')
