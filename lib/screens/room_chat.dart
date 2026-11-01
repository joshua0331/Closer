import 'package:flutter/material.dart';

import '../models/cloud_couple_store.dart';

class RoomChat extends StatefulWidget {
  const RoomChat({
    super.key,
    required this.store,
    this.initiallyExpanded = true,
  });
  final CloudCoupleStore store;
  final bool initiallyExpanded;
  @override
  State<RoomChat> createState() => _RoomChatState();
}

class _RoomChatState extends State<RoomChat> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || _text.text.trim().isEmpty) return;
    final message = _text.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.addMessage(message);
      if (mounted) _text.clear();
    } catch (_) {
      if (mounted) setState(() => _error = 'Message not sent. Please retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      initiallyExpanded: widget.initiallyExpanded,
      title: const Text('Room chat'),
      subtitle: const Text(
        'Chat together here. Submit testimony and evidence in the hearing for the judge to review.',
      ),
      childrenPadding: const EdgeInsets.all(12),
      children: [
        ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) {
            final messages = widget.store.messages
                .where((m) => m['kind'] != 'court')
                .toList()
                .reversed
                .toList();
            if (messages.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Say hello while you prepare your case.'),
              );
            }
            return SizedBox(
              height: 220,
              child: ListView.builder(
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final item = messages[index];
                  final mine = item['senderId'] == widget.store.uid;
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 420),
                      decoration: BoxDecoration(
                        color: mine ? const Color(0xFFFFE2D3) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mine
                                ? widget.store.yourName
                                : widget.store.partnerName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SelectableText(item['text'] as String? ?? ''),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        TextField(
          controller: _text,
          maxLength: 2000,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Message your partner'),
          onSubmitted: (_) => _send(),
        ),
        if (_error != null) Text(_error!),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send_outlined),
            label: Text(_busy ? 'Sending…' : 'Send'),
          ),
        ),
      ],
    ),
  );
}
