import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/smooth_scroll.dart';
import '../../models/meta_item.dart';
import '../../services/cinemeta_service.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/poster_grid.dart';
import '../home/home_screen.dart';

/// Live search over Cinemeta's movie and series catalogs.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _service = CinemetaService();
  final _ctl = TextEditingController();
  final _scroll = SmoothScrollController();
  Timer? _debounce;
  int _request = 0; // ignore stale responses

  String _query = '';
  bool _loading = false;
  String? _error;
  List<MetaItem> _movies = const [];
  List<MetaItem> _series = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    setState(() {}); // shows/hides the clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(text));
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    final id = ++_request;
    if (q.length < 2) {
      setState(() {
        _query = '';
        _loading = false;
        _error = null;
        _movies = const [];
        _series = const [];
      });
      return;
    }
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([
        _service.catalog('movie', search: q),
        _service.catalog('series', search: q),
      ]);
      if (!mounted || id != _request) return;
      setState(() {
        _movies = r[0];
        _series = r[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _request) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    void open(MetaItem m) => HomeScreen.openDetails(context, m);
    final hasResults = _movies.isNotEmpty || _series.isNotEmpty;

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(40, 20, 40, 48),
      children: [
        Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: GlassPanel(
              borderRadius: 999,
              blur: 22,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
              child: TextField(
                controller: _ctl,
                autofocus: true,
                onChanged: _onChanged,
                onSubmitted: _search,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search movies and series',
                  hintStyle: const TextStyle(color: Colors.white38),
                  icon: const Icon(Icons.search_rounded, color: Colors.white60),
                  suffixIcon: _ctl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () {
                            _ctl.clear();
                            _search('');
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_error != null)
          _Message(icon: Icons.cloud_off_rounded, text: _error!)
        else if (_query.isEmpty)
          const _Message(
            icon: Icons.travel_explore_rounded,
            text: 'Find any movie or series',
          )
        else if (!hasResults)
          _Message(
            icon: Icons.search_off_rounded,
            text: 'Nothing found for "$_query"',
          )
        else ...[
          if (_movies.isNotEmpty) ...[
            const _Heading('Movies'),
            PosterGrid(items: _movies, onOpen: open),
            const SizedBox(height: 36),
          ],
          if (_series.isNotEmpty) ...[
            const _Heading('Series'),
            PosterGrid(items: _series, onOpen: open),
          ],
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 70),
    child: Column(
      children: [
        Icon(icon, size: 44, color: Colors.white30),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 15),
        ),
      ],
    ),
  );
}
