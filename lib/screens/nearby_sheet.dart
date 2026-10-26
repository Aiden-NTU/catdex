import 'package:flutter/material.dart';

enum NearbyKind { wildCat, encounter, hub }

class NearbyItem {
  const NearbyItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.inRange,
    required this.onSelect,
  });

  final NearbyKind kind;
  final String id;
  final String title;
  final bool inRange;
  final VoidCallback onSelect;
}

Future<void> showNearbySheet(
  BuildContext context, {
  required List<NearbyItem> items,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => NearbySheet(items: items),
  );
}

class NearbySheet extends StatelessWidget {
  const NearbySheet({super.key, required this.items});

  final List<NearbyItem> items;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.48;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBF5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD6D3D1),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Nearby',
              style: TextStyle(
                color: Color(0xFF1C1917),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'Nothing close right now.\nKeep exploring the street.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF78716C)),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final (icon, color) = switch (item.kind) {
                        NearbyKind.wildCat => (
                          Icons.pets,
                          const Color(0xFFF97316),
                        ),
                        NearbyKind.encounter => (
                          Icons.sports_mma,
                          const Color(0xFFEF4444),
                        ),
                        NearbyKind.hub => (
                          Icons.place,
                          const Color(0xFFF59E0B),
                        ),
                      };
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        elevation: 1,
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: color,
                            child: Icon(icon, color: Colors.white),
                          ),
                          title: Text(
                            item.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1C1917),
                            ),
                          ),
                          subtitle: Text(
                            item.inRange ? 'In range' : 'Down the street',
                            style: TextStyle(
                              color: item.inRange
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF78716C),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: Text(
                            item.kind == NearbyKind.wildCat
                                ? 'Catch'
                                : item.kind == NearbyKind.encounter
                                ? 'Duel'
                                : 'Visit',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            item.onSelect();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
