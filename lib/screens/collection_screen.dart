import 'package:flutter/material.dart';

import '../data/cat_repository.dart';
import '../data/demo_pack.dart';
import '../models/cat.dart';
import '../widgets/cat_card.dart';
import 'cat_detail_screen.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, required this.repository});

  final CatRepository repository;

  @override
  State<CollectionScreen> createState() => CollectionScreenState();
}

class CollectionScreenState extends State<CollectionScreen> {
  List<CollectedCat> _cats = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cats = await widget.repository.getAll();
      if (!mounted) return;
      setState(() => _cats = cats);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: Semantics(
          label: 'Loading your cat collection',
          liveRegion: true,
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return _CollectionMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Collection unavailable',
        body: 'Your cats are safe. Check your connection and try again.',
        actionLabel: 'Try again',
        onAction: reload,
      );
    }
    if (_cats.isEmpty) {
      return _CollectionMessage(
        icon: Icons.pets_rounded,
        title: 'No cats yet',
        body: 'Catch one on the street, or take a practice cat to try a fight.',
        actionLabel: 'Get a practice cat',
        onAction: () async {
          await DemoPack.seedIfEmpty(widget.repository);
          if (!mounted) return;
          reload();
        },
      );
    }

    return RefreshIndicator(
      onRefresh: reload,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final minCardWidth = textScale > 1.3 ? 210.0 : 156.0;
          final columns = (constraints.maxWidth / minCardWidth).floor().clamp(
            1,
            4,
          );
          return Semantics(
            label: '${_cats.length} cats in your collection',
            child: GridView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.72,
              ),
              itemCount: _cats.length,
              itemBuilder: (context, i) {
                final cat = _cats[i];
                return CatCard(
                  cat: cat,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CatDetailScreen(
                          repository: widget.repository,
                          catId: cat.id,
                        ),
                      ),
                    );
                    reload();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CollectionMessage extends StatelessWidget {
  const _CollectionMessage({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Semantics(
          container: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: const Color(0xFFFDBA74)),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
