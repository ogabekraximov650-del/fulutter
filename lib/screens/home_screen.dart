import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/glass.dart';
import '../services/cache_service.dart';
import 'anime_detail_screen.dart';

const String API_BASE = 'https://aniraxuzapp.ogabekraximov650.workers.dev';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _animes = [];
  bool _isLoading = true;
  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ── Connectivity ─────────────────────────────────────────────
  void _listenConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);

      if (!isOnline) {
        // Internet o'chdi
        _wasOffline = true;
        if (mounted) setState(() => _isOffline = true);
      } else if (_wasOffline) {
        // Internet qayta yoqildi — avtomatik yangilash
        _wasOffline = false;
        if (mounted) setState(() => _isOffline = false);
        _fetchFromApi(force: true);
      }
    });
  }

  // ── Ma'lumot yuklash ─────────────────────────────────────────

  /// Ilova ochilganda: avval keshdan ko'rsat, keyin API'dan background yangilash.
  Future<void> _loadData() async {
    // 1. Keshdan tezkor ko'rsatish
    final cached = await CacheService.getAnimes();
    if (cached != null && mounted) {
      setState(() {
        _animes = cached;
        _isLoading = false;
      });
      // Background'da API'dan yangilash (UI bloklanmaydi)
      _fetchFromApi();
      return;
    }

    // 2. Kesh yo'q — API'dan yuklab ol
    await _fetchFromApi(showLoading: true);
  }

  /// API'dan ma'lumot olish va keshga saqlash.
  Future<void> _fetchFromApi({
    bool force = false,
    bool showLoading = false,
  }) async {
    if (showLoading && mounted) setState(() => _isLoading = true);

    try {
      final res = await http
          .get(Uri.parse('$API_BASE/api/anime'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 && mounted) {
        final data = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        await CacheService.saveAnimes(data);
        setState(() {
          _animes = data;
          _isLoading = false;
          _isOffline = false;
        });
      }
    } catch (_) {
      // Internet yo'q yoki xato — kesh ko'rsatib davom etadi
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isOffline = true;
        });
      }
    }
  }

  /// Pull-to-refresh: keshni tozalab API'dan majburiy yangilash.
  Future<void> _onRefresh() async {
    await CacheService.clearCache();
    await _fetchFromApi(force: true);
  }

  // ── UI ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      // Google-style aylanuvchi yangilash indikatoru
      onRefresh: _onRefresh,
      color: AppColors.accent,
      backgroundColor: AppColors.card,
      strokeWidth: 2.5,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // ── Header ────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fulutter',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Anime dunyosi',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.45),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Offline belgisi
                  if (_isOffline)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off_rounded,
                              size: 14, color: Colors.orange.shade300),
                          const SizedBox(width: 4),
                          Text(
                            'Offline',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade300,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(Icons.notifications_none_rounded,
                        color: Colors.white.withOpacity(0.7), size: 22),
                  ),
                ],
              ),
            ),
          ),

          // ── Offline xabari ────────────────────────────────
          if (_isOffline && _animes.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Keshdan ko\'rsatilmoqda • Yuqoriga torting',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade400,
                  ),
                ),
              ),
            ),

          // ── Sarlavha ──────────────────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Text(
                'Ommabop anime',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // ── Grid ──────────────────────────────────────────
          if (_isLoading)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 260,
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(AppColors.accent),
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else if (_animes.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 260,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isOffline
                            ? Icons.wifi_off_rounded
                            : Icons.movie_creation_outlined,
                        size: 52,
                        color: Colors.white.withOpacity(0.2),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isOffline
                            ? 'Internet yo\'q — yuqoriga torting'
                            : 'Anime topilmadi',
                        style: TextStyle(color: Colors.white.withOpacity(0.4)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.65,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      RepaintBoundary(child: AnimeCard(anime: _animes[index])),
                  childCount: _animes.length,
                  addRepaintBoundaries: false,
                  addAutomaticKeepAlives: false,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

// ── Anime kartochkasi ─────────────────────────────────────────

class AnimeCard extends StatelessWidget {
  final Map<String, dynamic> anime;
  const AnimeCard({super.key, required this.anime});

  @override
  Widget build(BuildContext context) {
    final photoUrl = anime['photo_url'] as String?;

    return GlassTappable(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 280),
            pageBuilder: (_, animation, __) => AnimeDetailScreen(anime: anime),
            transitionsBuilder: (_, animation, __, child) {
              final curved =
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
              return FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween(begin: 0.97, end: 1.0).animate(curved),
                  child: child,
                ),
              );
            },
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: AppColors.card,
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.32),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Rasm — diskdan keshlanadi (cached_network_image)
                    if (photoUrl != null)
                      CachedNetworkImage(
                        imageUrl: photoUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 240,
                        placeholder: (_, __) => Container(
                          color: AppColors.cardAlt,
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(AppColors.accent),
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.cardAlt,
                          child: const Center(
                            child: Icon(Icons.movie_creation_outlined,
                                size: 36, color: Colors.white38),
                          ),
                        ),
                      )
                    else
                      Container(
                        color: AppColors.cardAlt,
                        child: const Center(
                          child: Icon(Icons.movie_creation_outlined,
                              size: 36, color: Colors.white38),
                        ),
                      ),

                    // Pastdan qorayuvchi gradient
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 60,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [AppColors.card, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Matn qismi
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anime['name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        anime['janri'] ?? '',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
