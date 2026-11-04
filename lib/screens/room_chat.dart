import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:flutter/services.dart';

import '../services/photo_media.dart';
import '../localization/closer_localizations.dart';
import '../models/cloud_couple_store.dart';

class RoomChat extends StatefulWidget {
  const RoomChat({
    super.key,
    required this.store,
    required this.onAttach,
    required this.onInvite,
    required this.sessionBuilder,
  });

  final CloudCoupleStore store;
  final Future<void> Function() onAttach;
  final VoidCallback onInvite;
  final Widget Function(Map<String, dynamic>) sessionBuilder;

  @override
  State<RoomChat> createState() => _RoomChatState();
}

class _RoomChatState extends State<RoomChat> {
  final _text = TextEditingController();
  final _scrollController = ScrollController();
  bool _busy = false;
  bool _showSuggestions = true;
  bool _showDistanceBanner = true;
  String? _error;
  Map<String, dynamic>? _replyTo;

  @override
  void dispose() {
    _text.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  LatLng? _point(dynamic item) {
    if (item is Map && item['lat'] is num && item['lon'] is num) {
      return LatLng(
        (item['lat'] as num).toDouble(),
        (item['lon'] as num).toDouble(),
      );
    }
    return null;
  }

  List<String> _suggestions = [];
  bool _suggesting = false;
  String? _suggestionError;
  Future<void> _requestSuggestions() async {
    if (_suggesting) return;
    setState(() {
      _suggesting = true;
      _suggestionError = null;
    });
    try {
      final response = await widget.store.request(
        'couple/chat-suggestions',
        body: {'consent': true},
      );
      final data = jsonDecode(response.body) as Map;
      if (mounted)
        setState(
          () => _suggestions = List<String>.from(data['suggestions'] as List),
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _suggestionError =
              'AI suggestions are unavailable. Tap to retry.',
        );
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  void _useSuggestion(String value) {
    _text.text = value;
    _text.selection = TextSelection.collapsed(offset: value.length);
    setState(() => _showSuggestions = false);
  }

  Future<void> _send() async {
    final message = _text.text.trim();
    if (_busy || message.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.store.addMessage(message, replyTo: _replyTo);
      if (mounted) {
        _text.clear();
        setState(() => _replyTo = null);
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to send. Tap to retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFAF6F0),
        borderRadius: BorderRadius.zero,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A3B32).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0xFFF2EAE4)),
      ),
      child: Column(
        children: [
          if (_showDistanceBanner) _buildDistanceBanner(scheme),
          _buildFeed(scheme),
          if (_showSuggestions)
            if (_suggestions.isNotEmpty)
              _buildSuggestions(_suggestions)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    TextButton.icon(
                      onPressed: _suggesting ? null : _requestSuggestions,
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: Text(
                        _suggesting
                            ? 'Asking Meta…'
                            : _suggestionError ??
                                  'Suggest replies with Meta AI',
                      ),
                    ),
                    const Text(
                      'Shares recent chat text with Meta to suggest replies. Nothing is sent to your partner until you tap Send.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF756A66)),
                    ),
                  ],
                ),
              ),
          if (_replyTo != null)
            ListTile(
              dense: true,
              title: Text(
                '${tr('Reply')}: ${_replyTo!['text']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                onPressed: () => setState(() => _replyTo = null),
                icon: const Icon(Icons.close),
              ),
            ),
          _buildInput(primary),
          if (_error != null)
            GestureDetector(
              onTap: _send,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: scheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDistanceBanner(ColorScheme scheme) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final locations = widget.store.locations;
        final me = _point(locations[widget.store.uid]);
        final partner = _point(locations[widget.store.partnerUid]);
        final yourName = widget.store.yourName.isNotEmpty
            ? widget.store.yourName
            : 'You';
        final partnerName = widget.store.partnerName.isNotEmpty
            ? widget.store.partnerName
            : 'Partner';

        String distanceText = 'Location not shared yet';
        bool isNearby = false;

        if (me != null && partner != null) {
          final meters = Geolocator.distanceBetween(
            me.latitude,
            me.longitude,
            partner.latitude,
            partner.longitude,
          );
          isNearby = meters < 500;
          if (meters < 1000) {
            distanceText = '${meters.toStringAsFixed(0)} m apart';
          } else {
            distanceText = '${(meters / 1000).toStringAsFixed(1)} km apart';
          }
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isNearby
                  ? [const Color(0xFFE8F5E9), const Color(0xFFF1F8E9)]
                  : [const Color(0xFFFFF3EE), const Color(0xFFFAF7F2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isNearby
                  ? const Color(0xFFA5D6A7)
                  : const Color(0xFFFFD8C2),
              width: 1.2,
            ),
          ),
          child: Column(
            children: [
              // Top row: Distance text & close button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          isNearby ? Icons.favorite : Icons.near_me_rounded,
                          size: 14,
                          color: isNearby
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFB85842),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Our distance: $distanceText',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: isNearby
                                  ? const Color(0xFF1B5E20)
                                  : const Color(0xFF5A3E36),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _showDistanceBanner = false),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Color(0xFF8C584A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Middle row: User avatar -- dotted line -- Partner avatar
              Row(
                children: [
                  // Your initial / avatar
                  CircleAvatar(
                    radius: 14,
                    foregroundImage: _avatar(widget.store.avatarPath),
                    backgroundColor: scheme.primary.withValues(alpha: 0.2),
                    child: Text(
                      yourName[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Dotted visual line in between
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const dashWidth = 4.0;
                        const dashSpace = 4.0;
                        final dashCount =
                            (constraints.maxWidth / (dashWidth + dashSpace))
                                .floor();
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(dashCount, (_) {
                            return Container(
                              width: dashWidth,
                              height: 1.5,
                              color: const Color(0xFFD3B8AC),
                            );
                          }),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Partner initial / avatar
                  CircleAvatar(
                    radius: 14,
                    foregroundImage: _avatar(widget.store.partnerAvatarPath),
                    backgroundColor: isNearby
                        ? Colors.green.shade200
                        : const Color(0xFFFFD8C2),
                    child: Text(
                      partnerName[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isNearby
                            ? const Color(0xFF1B5E20)
                            : const Color(0xFF8C584A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Bottom small status text
              Text(
                isNearby
                    ? 'You are close to each other! ✨'
                    : 'Connected across the map',
                style: TextStyle(
                  fontSize: 11,
                  color: isNearby
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF9E8E85),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  ImageProvider? _avatar(String? path) {
    if (path == null) return null;
    return (photoImage(path) as Image).image;
  }

  Widget _buildFeed(ColorScheme scheme) => Expanded(
    child: ColoredBox(
      color: const Color(0xFFF3ECE4),
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final messages = widget.store.messages.reversed.toList();
          if (messages.isEmpty)
            return Center(
              child: Text(
                tr('Your story starts here. Send a quick wave! 👋'),
                textAlign: TextAlign.center,
              ),
            );
          return ListView.builder(
            controller: _scrollController,
            reverse: true,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final item = messages[index];
              if (item['kind'] == 'court') return widget.sessionBuilder(item);
              final mine = item['senderId'] == widget.store.uid;
              final text = item['text'] as String? ?? '';
              final time = DateTime.tryParse(item['createdAt'] as String? ?? '')
                  ?.toLocal();
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .72,
                  ),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: mine ? scheme.primary : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(mine ? 20 : 6),
                      bottomRight: Radius.circular(mine ? 6 : 20),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: mine ? scheme.onPrimary : const Color(0xFF3D322C),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          mine
                              ? widget.store.yourName
                              : widget.store.partnerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (item['replyTo'] is Map)
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: const Color(0x22FFFFFF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${tr('Reply')}: ${(item['replyTo'] as Map)['text']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (item['photoPath'] is String)
                          GestureDetector(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (context) => Dialog(
                                child: Stack(
                                  children: [
                                    InteractiveViewer(
                                      child: photoImage(
                                        item['photoPath'] as String,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: IconButton.filled(
                                        onPressed: () => Navigator.pop(context),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: photoImage(
                                item['photoPath'] as String,
                                height: 160,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        if (text.isNotEmpty)
                          Text(
                            text,
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (time != null)
                              Text(
                                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            if (item['hearted'] == true)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(
                                  Icons.favorite,
                                  color: Color(0xFFFFA5B5),
                                  size: 16,
                                ),
                              ),
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.more_horiz,
                                size: 18,
                                color: mine ? scheme.onPrimary : scheme.primary,
                              ),
                              onSelected: (value) async {
                                if (value == 'reply')
                                  setState(() => _replyTo = item);
                                if (value == 'copy')
                                  await Clipboard.setData(
                                    ClipboardData(text: text),
                                  );
                                if (value == 'heart') {
                                  try {
                                    await widget.store.toggleHeart(
                                      item['id'] as String,
                                    );
                                  } catch (_) {
                                    if (mounted)
                                      setState(
                                        () => _error = 'Could not update reaction. Please retry.',
                                      );
                                  }
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'reply',
                                  child: Text(tr('Reply')),
                                ),
                                PopupMenuItem(
                                  value: 'heart',
                                  child: Text(
                                    tr(
                                      item['heartedByMe'] == true
                                          ? 'Remove heart'
                                          : 'Add a heart',
                                    ),
                                  ),
                                ),
                                if (text.isNotEmpty)
                                  PopupMenuItem(
                                    value: 'copy',
                                    child: Text(tr('Copy text')),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );

  Widget _buildSuggestions(List<String> suggestions) {
    return Container(
      color: const Color(0xFFF3ECE4),
      padding: const EdgeInsets.fromLTRB(14, 4, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFE5A93B)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(
                          s,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF5A4532),
                          ),
                        ),
                        backgroundColor: const Color(0xFFFFF9E6),
                        side: const BorderSide(color: Color(0xFFFCE8B2)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        onPressed: () => _useSuggestion(s),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _showSuggestions = false),
            icon: const Icon(Icons.close, size: 16, color: Color(0xFF9E8E85)),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(Color primary) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _busy ? null : widget.onAttach,
            tooltip: tr('Attach chat photo'),
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          // Moved here from the removed header so sessions can still be started.
          IconButton(
            onPressed: widget.onInvite,
            tooltip: tr('Invite partner to a session'),
            icon: const Icon(Icons.auto_awesome_rounded),
          ),
          Expanded(
            child: TextField(
              controller: _text,
              minLines: 1,
              maxLines: 3,
              maxLength: 2000,
              decoration: InputDecoration(
                hintText: tr('Write a message…'),
                counterText: '',
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF9E8E85),
                ),
                filled: true,
                fillColor: const Color(0xFFF7F2EC),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
            ),
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 16),
            label: Text(
              tr(_busy ? 'Sending…' : 'Send'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
