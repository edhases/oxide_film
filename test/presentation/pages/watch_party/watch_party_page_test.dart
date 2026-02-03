import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:oxide_film/data/services/watch_party_service.dart';
import 'package:oxide_film/presentation/pages/watch_party/watch_party_page.dart';

// Manual Mock for Service
class MockWatchPartyService extends ChangeNotifier
    implements WatchPartyService {
  @override
  WatchPartyState state = WatchPartyState.idle;

  @override
  String myName = 'Test User';

  @override
  List<WatchPartyParticipant> participants = [];

  @override
  List<ChatMessage> chatMessages = [];

  @override
  WatchPartyBackendType backendType = WatchPartyBackendType.supabase;

  @override
  WatchPartyRoom? room;

  @override
  bool isHost = false;

  @override
  bool isPlaying = false; // Stub

  @override
  String get myId => 'test_id';

  @override
  String? currentRoomCode;

  @override
  String? error;

  @override
  void setMyName(String name) {
    myName = name;
    notifyListeners();
  }

  @override
  Future<bool> hostRoom({String? mediaUrl, String? mediaTitle}) async {
    isHost = true;
    state = WatchPartyState.connected;
    room = WatchPartyRoom(
      id: 'HOST12',
      hostId: 'me',
      hostName: myName,
      mediaTitle: mediaTitle,
      mediaUrl: mediaUrl,
    );
    notifyListeners();
    return true;
  }

  @override
  Future<bool> joinRoom(String roomCode) async {
    isHost = false;
    currentRoomCode = roomCode;
    state = WatchPartyState.connected;
    participants = [
      WatchPartyParticipant(
        id: 'other',
        name: 'Other',
        isHost: true,
        joinedAt: DateTime.now(),
      ),
      WatchPartyParticipant(
        id: 'me',
        name: myName,
        isHost: false,
        joinedAt: DateTime.now(),
      ),
    ];
    notifyListeners();
    return true;
  }

  @override
  Future<void> leaveRoom() async {
    state = WatchPartyState.idle;
    notifyListeners();
  }

  @override
  void sendChatMessage(String message) {
    chatMessages.add(
      ChatMessage(
        id: '1',
        senderId: 'me',
        senderName: myName,
        message: message,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  // Stubs for other members to avoid unimplemented errors
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockWatchPartyService mockService;

  setUp(() {
    GetIt.I.reset();
    mockService = MockWatchPartyService();
    GetIt.I.registerSingleton<WatchPartyService>(mockService);
  });

  Widget createWidget() {
    return MaterialApp(
      home: const WatchPartyPage(
        mediaTitle: 'Test Movie',
        mediaUrl: 'http://test.com',
      ),
    );
  }

  testWidgets('WatchPartyPage shows idle state initially', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createWidget());

    expect(find.text('Спільний перегляд'), findsOneWidget);
    expect(find.text('Ваше ім\'я'), findsOneWidget);
    expect(
      find.text('Створити кімнату'),
      findsAtLeastNWidgets(1),
    ); // Title + Button
    expect(find.text('Приєднатися до кімнати'), findsOneWidget);
  });

  testWidgets('Inputting name and hosting changes state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createWidget());

    // Enter name
    await tester.enterText(
      find.ancestor(
        of: find.text('Введіть ваше ім\'я'),
        matching: find.byType(TextField),
      ),
      'MyName',
    );
    await tester.pump();

    // Click host
    await tester.tap(find.widgetWithText(FilledButton, 'Створити кімнату'));
    await tester.pump(); // Start async
    await tester.pump(); // Finish async

    expect(mockService.state, WatchPartyState.connected);
    expect(find.text('Ви хост'), findsOneWidget);
  });

  testWidgets('Inputting code and joining changes state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createWidget());

    // Enter code
    await tester.enterText(
      find.ancestor(of: find.text('ABCD12'), matching: find.byType(TextField)),
      'ABCDEF',
    );
    await tester.pump();

    // Click join
    await tester.tap(find.widgetWithText(FilledButton, 'Приєднатися'));
    await tester.pump(); // Start async
    await tester.pump(); // Finish async

    expect(mockService.state, WatchPartyState.connected);
    expect(find.text('Підключено'), findsOneWidget);
    // Should show participants tab
    expect(find.text('Other'), findsOneWidget);
  });

  testWidgets('Sending chat message works', (WidgetTester tester) async {
    // Start in connected state
    mockService.joinRoom('CODE');
    await tester.pumpWidget(createWidget());

    // Switch to Chat tab
    await tester.tap(find.text('Чат'));
    await tester.pumpAndSettle();

    // Enter message
    await tester.enterText(
      find.byType(TextField).last,
      'Hello Chat',
    ); // Chat input is likely the last text field
    await tester.tap(find.byKey(const Key('chat_send_button')));
    await tester.pump();

    expect(mockService.chatMessages.length, 1);
    expect(find.text('Hello Chat'), findsOneWidget);
  });
}
