import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/favorite.dart';
import '../services/favorites_service.dart';
import '../services/auth_service.dart';
import '../services/share_service.dart';
import '../services/logger_service.dart';
import '../widgets/favorite_heart_button.dart';
import 'login_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Favorite> _favorites = [];
  bool _isLoading = false;
  String? _error;
  bool _isSignedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadFavorites();
  }

  Future<void> _checkAuthAndLoadFavorites() async {
    final isSignedIn = await AuthService.isSignedIn();
    
    if (!isSignedIn) {
      setState(() {
        _isSignedIn = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isSignedIn = true;
    });
    
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final favorites = await FavoritesService.getFavorites();
      if (mounted) {
        setState(() {
          _favorites = favorites;
          _isLoading = false;
        });
      }
    } catch (e) {
      LoggerService.error('Error loading favorites', error: e);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshFavorites() async {
    await _loadFavorites();
  }

  void _onFavoriteRemoved() {
    // Refresh the list when a favorite is removed
    _refreshFavorites();
  }

  Widget _buildFavoriteCard(Favorite favorite) {
    final quote = favorite.quote;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quote.quote,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '— ${quote.author}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FavoriteHeartButton(
                  quoteId: favorite.quoteId,
                  initialIsFavorite: true,
                  onFavoriteChanged: _onFavoriteRemoved,
                  size: 20,
                ),
              ],
            ),
            if (quote.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: quote.tags.map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      tag,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Favorited: ${_formatDate(favorite.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copyQuote(quote.quote, quote.author),
                  tooltip: 'Copy quote',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(
                    kIsWeb ? Icons.share : CupertinoIcons.share,
                    size: 18
                  ),
                  onPressed: () => _shareQuote(quote.quote, quote.author, favorite.quoteId, quote.tags),
                  tooltip: 'Share quote',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return isoDate;
    }
  }

  void _copyQuote(String quote, String author) {
    final text = '"$quote" — $author';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check, color: Colors.white),
            SizedBox(width: 8),
            Text('Quote copied to clipboard'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareQuote(String quote, String author, String quoteId, [List<String>? tags]) {
    ShareService.shareQuote(
      context: context,
      quote: quote,
      author: author,
      quoteId: quoteId,
      tags: tags,
    );
  }

  Widget _buildSignInPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              'Sign In to View Favorites',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sign in to save your favorite quotes and access them anytime.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const LoginScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.login),
              label: const Text('Sign In'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              'No Favorites Yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Start exploring quotes and tap the heart icon to save your favorites!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.explore),
              label: const Text('Explore Quotes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Favorites'),
        actions: [
          if (_isSignedIn && _favorites.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshFavorites,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: !_isSignedIn 
        ? _buildSignInPrompt()
        : _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading favorites',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _refreshFavorites,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : _favorites.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _refreshFavorites,
                  child: ListView.builder(
                    itemCount: _favorites.length,
                    itemBuilder: (context, index) {
                      return _buildFavoriteCard(_favorites[index]);
                    },
                  ),
                ),
    );
  }
}