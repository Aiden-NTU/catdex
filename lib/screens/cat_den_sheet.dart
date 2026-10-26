import 'package:flutter/material.dart';

import '../data/cat_repository.dart';
import '../data/demo_pack.dart';
import '../models/cat.dart';
import '../widgets/cat_card.dart';
import 'cat_detail_screen.dart';

enum _DenSort { recent, stars, power }

Future<void> showCatDenSheet(
  BuildContext context, {
  required CatRepository repository,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => CatDenSheet(repository: repository),
  );
}

class CatDenSheet extends StatefulWidget {
  const CatDenSheet({super.key, required this.repository});

  final CatRepository repository;

  @override
  State<CatDenSheet> createState() => _CatDenSheetState();
}

class _CatDenSheetState extends State<CatDenSheet> {
  List<CollectedCat> _cats = [];
  bool _loading = true;
  _DenSort _sort = _DenSort.recent;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final cats = await widget.repository.getAll();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _loading = false;
    });
  }

  List<CollectedCat> get _sorted {
    final list = List<CollectedCat>.of(_cats);
    switch (_sort) {
      case _DenSort.recent:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _DenSort.stars:
        list.sort((a, b) => b.stars.compareTo(a.stars));
      case _DenSort.power:
        list.sort((a, b) => b.battlePower.compareTo(a.battlePower));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.92;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF7ED),
            Color(0xFFF5E6D3),
            Color(0xFFE7D5C0),
          ],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD6D3D1),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cat Den',
                        style: TextStyle(
                          color: Color(0xFF1C1917),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _loading
                            ? '…'
                            : '${_cats.length} card${_cats.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Color(0xFF78716C),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Color(0xFF44403C)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                for (final sort in _DenSort.values) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (sort) {
                        _DenSort.recent => 'Recent',
                        _DenSort.stars => 'Stars',
                        _DenSort.power => 'Power',
                      }),
                      selected: _sort == sort,
                      onSelected: (_) => setState(() => _sort = sort),
                      selectedColor: const Color(0xFFEA580C),
                      labelStyle: TextStyle(
                        color: _sort == sort
                            ? Colors.white
                            : const Color(0xFF44403C),
                        fontWeight: FontWeight.w700,
                      ),
                      backgroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Color(0xFFEA580C),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pets, size: 44, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const Text(
                'Your den is empty',
                style: TextStyle(
                  color: Color(0xFF1C1917),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Catch a cat on the map to start your collection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF78716C), fontSize: 15),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () async {
                  await DemoPack.seedIfEmpty(widget.repository);
                  await _reload();
                },
                child: const Text(
                  'Load a demo card',
                  style: TextStyle(color: Color(0xFFA8A29E)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final cats = _sorted;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemCount: cats.length,
      itemBuilder: (context, i) {
        final cat = cats[i];
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
            await _reload();
          },
        );
      },
    );
  }
}
