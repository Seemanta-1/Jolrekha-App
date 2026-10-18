import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../theme.dart';

/// Realtime group chat for everyone who joined a clean-up drive.
class EventChatScreen extends StatefulWidget {
  final CleanupEvent event;
  final AppUser me;
  const EventChatScreen({super.key, required this.event, required this.me});

  @override
  State<EventChatScreen> createState() => _EventChatScreenState();
}

class _EventChatScreenState extends State<EventChatScreen> {
  late final _messages = EventService.messages(widget.event.id);
  final _text = TextEditingController();

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    try {
      await EventService.send(widget.event.id, widget.me, t);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('পাঠানো যায়নি: $e')));
    }
  }

  String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.title, style: const TextStyle(fontSize: 16)),
          Text('${e.area} • ${whenBn(e.startAt)} • ${e.members.length} জন',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: _messages,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('চ্যাট খোলা যায়নি: ${snap.error}', textAlign: TextAlign.center));
              }
              final list = (snap.data ?? []).reversed.toList();
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final m = list[i];
                  final mine = m.uid == widget.me.uid;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: mine ? JR.water : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (!mine)
                          Text(m.name,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: JR.water)),
                        Text(m.text, style: TextStyle(color: mine ? Colors.white : JR.ink)),
                        Text(_hm(m.at), style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : Colors.black45)),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'টিমকে কিছু লিখুন…'),
                ),
              ),
              IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}
