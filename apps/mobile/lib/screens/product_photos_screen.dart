import 'package:flutter/material.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/shop_repository.dart';
import '../widgets/product_image_gallery.dart';

class ProductPhotosScreen extends StatefulWidget {
  const ProductPhotosScreen({super.key});

  @override
  State<ProductPhotosScreen> createState() => _ProductPhotosScreenState();
}

class _ProductPhotosScreenState extends State<ProductPhotosScreen> {
  final ShopRepository _repository = ShopRepository();
  late Future<_PhotoData> _future;

  bool get _canManage =>
      AppSession.instance.can(AppPermission.manageMerchandising);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Future.wait([
      _repository.products(),
      _repository.orders(),
    ]).then(
      (values) => _PhotoData(
        products: List<Map<String, dynamic>>.from(values[0]),
        orders: List<Map<String, dynamic>>.from(values[1]),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _reload();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PhotoData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const Material(
                child: TabBar(
                  tabs: [
                    Tab(text: 'Galerias', icon: Icon(Icons.photo_library_outlined)),
                    Tab(text: 'Pendentes', icon: Icon(Icons.shopping_bag_outlined)),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _GalleryList(
                      products: data.products,
                      repository: _repository,
                      canManage: _canManage,
                      onChanged: _refresh,
                    ),
                    _PendingOrders(
                      orders: data.orders,
                      products: data.products,
                      repository: _repository,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GalleryList extends StatelessWidget {
  const _GalleryList({
    required this.products,
    required this.repository,
    required this.canManage,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> products;
  final ShopRepository repository;
  final bool canManage;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text(
            'Fotografias dos artigos',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Cada artigo pode ter várias fotografias. A imagem marcada como capa é usada nas listagens e encomendas.',
          ),
          const SizedBox(height: 16),
          if (products.isEmpty)
            const Card(child: ListTile(title: Text('Ainda não existem artigos.')))
          else
            for (final product in products)
              _ProductPhotoCard(
                product: product,
                repository: repository,
                canManage: canManage,
                onChanged: onChanged,
              ),
        ],
      ),
    );
  }
}

class _ProductPhotoCard extends StatelessWidget {
  const _ProductPhotoCard({
    required this.product,
    required this.repository,
    required this.canManage,
    required this.onChanged,
  });

  final Map<String, dynamic> product;
  final ShopRepository repository;
  final bool canManage;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final cover = repository.publicImageUrl(product['photo_path']);
    return Card(
      child: ListTile(
        leading: SizedBox(
          width: 58,
          height: 58,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: cover == null
                ? const ColoredBox(
                    color: Color(0xFFECEFF1),
                    child: Icon(Icons.image_outlined),
                  )
                : Image.network(cover, fit: BoxFit.cover),
          ),
        ),
        title: Text(product['name']?.toString() ?? 'Artigo'),
        subtitle: Text(product['category']?.toString() ?? 'Merchandising'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => _ProductGalleryPage(
              product: product,
              repository: repository,
              canManage: canManage,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductGalleryPage extends StatelessWidget {
  const _ProductGalleryPage({
    required this.product,
    required this.repository,
    required this.canManage,
    required this.onChanged,
  });

  final Map<String, dynamic> product;
  final ShopRepository repository;
  final bool canManage;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(product['name']?.toString() ?? 'Artigo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          ProductImageGallery(
            repository: repository,
            productId: product['id'].toString(),
            coverPath: product['photo_path']?.toString(),
            canManage: canManage,
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.touch_app_outlined),
              title: Text('Miniaturas interativas'),
              subtitle: Text(
                'Toca numa miniatura para ampliar. No menu da foto podes defini-la como capa ou eliminá-la.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingOrders extends StatelessWidget {
  const _PendingOrders({
    required this.orders,
    required this.products,
    required this.repository,
  });

  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> products;
  final ShopRepository repository;

  @override
  Widget build(BuildContext context) {
    final byId = {
      for (final product in products) product['id'].toString(): product,
    };
    final pending = orders
        .where((order) =>
            order['status']?.toString() != 'delivered' &&
            order['status']?.toString() != 'cancelled')
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          'Encomendas pendentes',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text('A capa do artigo facilita a conferência visual da encomenda.'),
        const SizedBox(height: 16),
        if (pending.isEmpty)
          const Card(child: ListTile(title: Text('Não existem encomendas pendentes.')))
        else
          for (final order in pending)
            _PendingOrderCard(
              order: order,
              productsById: byId,
              repository: repository,
            ),
      ],
    );
  }
}

class _PendingOrderCard extends StatelessWidget {
  const _PendingOrderCard({
    required this.order,
    required this.productsById,
    required this.repository,
  });

  final Map<String, dynamic> order;
  final Map<String, Map<String, dynamic>> productsById;
  final ShopRepository repository;

  @override
  Widget build(BuildContext context) {
    final items = List<Map<String, dynamic>>.from(
      order['shop_order_items'] as List? ?? const [],
    );
    final member = order['members'];
    final client = member is Map
        ? member['full_name']?.toString() ?? 'Membro'
        : (order['external_name']?.toString() ?? 'Cliente');

    String article = 'Artigo';
    String variant = '';
    String? coverPath;
    if (items.isNotEmpty) {
      final first = items.first;
      final productId = first['product_id']?.toString();
      final product = productId == null ? null : productsById[productId];
      article = product?['name']?.toString() ??
          ((first['products'] is Map)
              ? first['products']['name']?.toString() ?? 'Artigo'
              : 'Artigo');
      coverPath = product?['photo_path']?.toString();
      final variantRow = first['product_variants'];
      if (variantRow is Map) {
        variant = variantRow['name']?.toString() ?? '';
      }
    }
    final cover = repository.publicImageUrl(coverPath);

    return Card(
      child: ListTile(
        leading: SizedBox(
          width: 64,
          height: 64,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: cover == null
                ? const ColoredBox(
                    color: Color(0xFFECEFF1),
                    child: Icon(Icons.image_outlined),
                  )
                : Image.network(cover, fit: BoxFit.cover),
          ),
        ),
        title: Text(article),
        subtitle: Text([
          client,
          if (variant.isNotEmpty) variant,
          _statusLabel(order['status']?.toString() ?? 'pending'),
        ].join(' · ')),
        trailing: const Icon(Icons.pending_actions_outlined),
      ),
    );
  }
}

class _PhotoData {
  const _PhotoData({required this.products, required this.orders});
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> orders;
}

String _statusLabel(String status) => switch (status) {
      'ordered' => 'Encomendado',
      'received' => 'Recebido',
      'pending' => 'Pendente',
      _ => status,
    };
