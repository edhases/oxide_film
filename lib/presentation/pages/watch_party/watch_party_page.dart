import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/services/watch_party_service.dart';

/// Page for creating or joining a watch party
class WatchPartyPage extends StatefulWidget {
  final String? mediaUrl;
  final String? mediaTitle;

  const WatchPartyPage({super.key, this.mediaUrl, this.mediaTitle});

  @override
  State<WatchPartyPage> createState() => _WatchPartyPageState();
}

class _WatchPartyPageState extends State<WatchPartyPage> {
  final _service = WatchPartyService();
  final _nameController = TextEditingController(text: 'User');
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _service.dispose();
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    setState(() {});

    // Auto-scroll chat
    if (_chatScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Спільний перегляд'),
        actions: [
          if (_service.state == WatchPartyState.connected)
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: 'Вийти з кімнати',
              onPressed: () async {
                await _service.leaveRoom();
              },
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    switch (_service.state) {
      case WatchPartyState.idle:
        return _buildIdleState(theme);
      case WatchPartyState.hosting:
      case WatchPartyState.joining:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Підключення...'),
            ],
          ),
        );
      case WatchPartyState.connected:
        return _buildConnectedState(theme);
      case WatchPartyState.error:
        return _buildErrorState(theme);
    }
  }

  Widget _buildIdleState(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Name input
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ваше ім\'я', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'Введіть ваше ім\'я',
                      prefixIcon: Icon(Icons.person),
                    ),
                    onChanged: (value) => _service.setMyName(value),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Host option
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tv, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Створити кімнату',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Створіть кімнату та запросіть друзів для спільного перегляду',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  if (widget.mediaTitle != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.movie, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.mediaTitle!,
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      _service.setMyName(_nameController.text);
                      await _service.hostRoom(
                        mediaUrl: widget.mediaUrl,
                        mediaTitle: widget.mediaTitle,
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Створити кімнату'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Join option
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.group, color: theme.colorScheme.secondary),
                      const SizedBox(width: 8),
                      Text(
                        'Приєднатися до кімнати',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Введіть IP-адресу та порт для підключення',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _hostController,
                          decoration: const InputDecoration(
                            hintText: '192.168.x.x',
                            labelText: 'IP адреса',
                            prefixIcon: Icon(Icons.computer),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _portController,
                          decoration: const InputDecoration(
                            hintText: '8080',
                            labelText: 'Порт',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      final host = _hostController.text.trim();
                      final port = int.tryParse(_portController.text.trim());

                      if (host.isEmpty || port == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Введіть IP адресу та порт'),
                          ),
                        );
                        return;
                      }

                      _service.setMyName(_nameController.text);
                      await _service.joinRoom(host, port);
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Приєднатися'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedState(ThemeData theme) {
    return Column(
      children: [
        // Room info bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Icon(
                _service.isHost ? Icons.tv : Icons.group,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _service.isHost ? 'Ви хост' : 'Підключено до хоста',
                      style: theme.textTheme.titleSmall,
                    ),
                    if (_service.room?.connectionString != null &&
                        _service.isHost)
                      Text(
                        'Код підключення: ${_service.room!.connectionString}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
              if (_service.isHost)
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: 'Копіювати код',
                  onPressed: () {
                    if (_service.room != null) {
                      Clipboard.setData(
                        ClipboardData(text: _service.room!.connectionString),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Код скопійовано'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people, size: 16),
                    const SizedBox(width: 4),
                    Text('${_service.participants.length}'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Main content
        Expanded(
          child: Row(
            children: [
              // Participants panel
              Container(
                width: 200,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: theme.dividerColor)),
                ),
                child: _buildParticipantsPanel(theme),
              ),

              // Chat panel
              Expanded(child: _buildChatPanel(theme)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantsPanel(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Учасники',
            style: theme.textTheme.titleSmall?.copyWith(color: Colors.grey),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _service.participants.length,
            itemBuilder: (context, index) {
              final participant = _service.participants[index];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: participant.isHost
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondary,
                  child: Text(
                    participant.name.isNotEmpty
                        ? participant.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                title: Text(participant.name, overflow: TextOverflow.ellipsis),
                subtitle: participant.isHost
                    ? Text(
                        'Хост',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 11,
                        ),
                      )
                    : null,
                trailing: participant.id == _service.myId
                    ? const Icon(Icons.person, size: 16)
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChatPanel(ThemeData theme) {
    return Column(
      children: [
        // Media info if available
        if (_service.room?.mediaTitle != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Row(
              children: [
                const Icon(Icons.movie, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _service.room!.mediaTitle!,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        // Chat header
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.chat, size: 20, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Чат',
                style: theme.textTheme.titleSmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),

        // Chat messages
        Expanded(
          child: _service.chatMessages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 48,
                        color: Colors.grey.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Напишіть перше повідомлення!',
                        style: TextStyle(
                          color: Colors.grey.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _service.chatMessages.length,
                  itemBuilder: (context, index) {
                    final message = _service.chatMessages[index];
                    final isMe = message.senderId == _service.myId;

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.6,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Text(
                                message.senderName,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            Text(
                              message.message,
                              style: TextStyle(
                                color: isMe ? Colors.white : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Chat input
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: const InputDecoration(
                    hintText: 'Написати повідомлення...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: _sendMessage,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => _sendMessage(_chatController.text),
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Помилка підключення', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              _service.error ?? 'Невідома помилка',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                await _service.leaveRoom();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Спробувати знову'),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;

    _service.sendChatMessage(text.trim());
    _chatController.clear();
  }
}
