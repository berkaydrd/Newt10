import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LeaderboardEntry {
  final String username;
  final String? profileImagePath;
  final double twrRatio;
  final int rank;

  const LeaderboardEntry({
    required this.username,
    required this.profileImagePath,
    required this.twrRatio,
    required this.rank,
  });

  factory LeaderboardEntry.fromMap(Map<String, dynamic> data) {
    final profileRaw =
        (data['profile_image_path'] ?? data['photoUrl'])?.toString();
    final String? profileImage =
        profileRaw != null && profileRaw.trim().isNotEmpty
            ? profileRaw.trim()
            : null;
    final num rawTwr = (data['twr_ratio'] as num?) ?? 0;
    final num rawRank = (data['rank'] as num?) ?? 0;

    return LeaderboardEntry(
      username: (data['username'] ?? '').toString(),
      profileImagePath: profileImage,
      twrRatio: rawTwr.toDouble(),
      rank: rawRank.toInt(),
    );
  }
}

class LeaderboardFrame extends StatefulWidget {
  const LeaderboardFrame({super.key});

  @override
  State<LeaderboardFrame> createState() => _LeaderboardFrameState();
}

class _LeaderboardFrameState extends State<LeaderboardFrame> {
  final Map<String, String> _periodLabels = const {
    'weekly': 'Haftalık',
    'monthly': 'Aylık',
    'yearly': 'Yıllık',
  };

  final Map<String, List<LeaderboardEntry>> _entriesCache = {};

  String _selectedPeriod = 'weekly';
  bool _expanded = false;

  Future<List<LeaderboardEntry>> _loadEntries(String period) async {
    if (_entriesCache.containsKey(period)) {
      return _entriesCache[period]!;
    }

    final doc = await FirebaseFirestore.instance
        .collection('leaderboards')
        .doc(period)
        .get();

    if (!doc.exists) return [];

    final data = doc.data();
    if (data == null) return [];

    final rawEntries = data['entries'];
    if (rawEntries is! List) return [];

    final entries = rawEntries
        .whereType<Map>()
        .map((entry) => LeaderboardEntry.fromMap(
            Map<String, dynamic>.from(entry)))
        .toList();

    _entriesCache[period] = entries;
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(25, 0, 0, 0),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Liderlik Tablosu',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _buildToggleButton(),
            ],
          ),
          const SizedBox(height: 12),
          _buildPeriodSelector(),
          const SizedBox(height: 16),
          FutureBuilder<List<LeaderboardEntry>>(
            future: _loadEntries(_selectedPeriod),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Liderlik tablosu yüklenemedi.'),
                );
              }

              final entries = snapshot.data ?? const <LeaderboardEntry>[];
              if (entries.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('Henüz yeterli veri yok.'),
                );
              }

              final visibleCount = _expanded ? 10 : 5;
              final visibleEntries =
                  entries.take(visibleCount).toList(growable: false);

              return Column(
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: visibleEntries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = visibleEntries[index];
                      final isTopThree = index < 3;
                      return _buildEntryTile(entry, isTopThree);
                    },
                  ),
                  if (entries.length > 5)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          setState(() => _expanded = !_expanded);
                        },
                        child: Text(
                          _expanded ? 'Daha Az Göster' : 'Tümünü Gör',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.leaderboard, size: 16, color: Colors.black54),
          SizedBox(width: 6),
          Text('Top 10', style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Row(
      children: _periodLabels.entries.map((entry) {
        final bool isSelected = _selectedPeriod == entry.key;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedPeriod = entry.key;
                _expanded = false;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 1.2),
              ),
              child: Center(
                child: Text(
                  entry.value,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEntryTile(LeaderboardEntry entry, bool highlight) {
    final double percent = entry.twrRatio * 100;
    final String percentText =
        '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(2)}%';
    final Color percentColor =
        percent >= 0 ? Colors.green.shade700 : Colors.red.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? Colors.amber.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? Colors.amber.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          _buildRankBadge(entry.rank, highlight),
          const SizedBox(width: 10),
          _buildAvatar(entry.profileImagePath, highlight),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ),
          Text(
            percentText,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: percentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankBadge(int rank, bool highlight) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: highlight ? Colors.amber.shade200 : Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          rank.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildAvatar(String? url, bool highlight) {
    final double radius = highlight ? 18 : 16;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: url != null ? NetworkImage(url) : null,
      child: url == null
          ? Icon(Icons.person, size: radius, color: Colors.grey.shade600)
          : null,
    );
  }
}
