import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../widgets/glass.dart';
import 'anime_detail_screen.dart';

const String API_BASE = 'https://aniraxuzapp.ogabekraximov650.workers.dev';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final res = await http.get(Uri.parse('$API_BASE/api/anime'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List;
        final allAnimes = data.cast<Map<String, dynamic>>();
        final filtered = allAnimes
            .where((anime) =>
                (anime['name'] as String?)
                    ?.toLowerCase()
                    .contains(query.toLowerCase()) ??
                false)
            .toList();
        setState(() {
          _results = filtered;
          _hasSearched = true;
        });
      }
    } catch (e) {
      setState(() => _hasSearched = true);
    } finally {
      setState(() => _isSearching = false);
    }
  }

  void _clear() {
    _searchCtrl.clear();
    setState(() {
      _results = [];
      _hasSearched = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          // Qidiruv maydoni — o'ng tomonda x tugmasi
          Glass(
            borderRadius: 18,
            blur: 16,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    onChanged: _search,
                    decoration: InputDecoration(
                      hintText: 'Anime qidirish...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.54)),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                // X tugmasi — faqat matn yozilgan bo'lsa ko'rinadi
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _searchCtrl.text.isNotEmpty
                      ? GestureDetector(
                          key: const ValueKey('clear'),
                          onTap: _clear,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('empty')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Natijalar
          Expanded(
            child: _isSearching
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(Colors.white.withOpacity(0.6)),
                    ),
                  )
                : _results.isEmpty && _hasSearched
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded,
                                size: 48, color: Colors.white24),
                            const SizedBox(height: 12),
                            Text('Qidiruv natijalari topilmadi',
                                style: TextStyle(color: Colors.white.withOpacity(0.54))),
                          ],
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search_rounded,
                                    size: 48, color: Colors.white24),
                                const SizedBox(height: 12),
                                Text('Anime nomini yozib qidiruv qiling',
                                    style: TextStyle(color: Colors.white.withOpacity(0.54))),
                              ],
                            ),
                          )
                        : GridView.builder(
                            physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics()),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.68,
                            ),
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final anime = _results[i];
                              return _AnimeSearchCard(anime: anime);
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _AnimeSearchCard extends StatelessWidget {
  final Map<String, dynamic> anime;
  const _AnimeSearchCard({required this.anime});

  @override
  Widget build(BuildContext context) {
    return GlassTappable(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 320),
            pageBuilder: (_, animation, __) => AnimeDetailScreen(anime: anime),
            transitionsBuilder: (_, animation, __, child) {
              final curved =
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
                      .animate(curved),
                  child: child,
                ),
              );
            },
          ),
        );
      },
      child: GlassLite(
        borderRadius: 18,
        tint: 0.08,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  image: DecorationImage(
                    image: NetworkImage(anime['photo_url'] ?? ''),
                    fit: BoxFit.cover,
                    onError: (_, __) {},
                  ),
                  color: Colors.white.withOpacity(0.10),
                ),
                child: anime['photo_url'] == null
                    ? const Center(
                        child: Icon(Icons.movie_creation_outlined,
                            size: 40, color: Colors.white70),
                      )
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    anime['name'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                  ),
                  Text(
                    anime['janri'] ?? '',
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
