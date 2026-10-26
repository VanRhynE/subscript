import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/services/notification_service.dart';
import '../data/models/subscription_local.dart';
import '../data/services/database_service.dart';

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService();
  ref.onDispose(service.close);
  return service;
});

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

// ---------------------------------------------------------------------------
// Reactive data
// ---------------------------------------------------------------------------

/// Live list of subscriptions, soonest renewal first.
final subscriptionsProvider = StreamProvider<List<SubscriptionLocal>>((ref) {
  return ref.watch(databaseServiceProvider).watchAll();
});

/// Sum of every subscription normalised to a monthly cost.
final monthlyOverheadProvider = Provider<double>((ref) {
  final subs = ref.watch(subscriptionsProvider).valueOrNull ?? const [];
  return subs.fold<double>(0, (sum, s) => sum + s.monthlyCost);
});

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

final subscriptionControllerProvider =
    StateNotifierProvider<SubscriptionController, AsyncValue<void>>((ref) {
  return SubscriptionController(
    database: ref.watch(databaseServiceProvider),
    notifications: ref.watch(notificationServiceProvider),
  );
});

class SubscriptionController extends StateNotifier<AsyncValue<void>> {
  SubscriptionController({
    required DatabaseService database,
    required NotificationService notifications,
  })  : _database = database,
        _notifications = notifications,
        super(const AsyncData(null));

  final DatabaseService _database;
  final NotificationService _notifications;
  final Uuid _uuid = const Uuid();

  /// Persists a new subscription, then schedules its renewal reminder.
  /// Returns true on success. A failed reminder never loses the saved record.
  Future<bool> addSubscription({
    required String name,
    required double cost,
    required String billingCycle,
    required DateTime nextBillingDate,
    required String category,
    required String colorHex,
    required int reminderDaysBefore,
  }) async {
    state = const AsyncLoading();

    final result = await AsyncValue.guard<SubscriptionLocal>(() async {
      final sub = SubscriptionLocal()
        ..uuid = _uuid.v4()
        ..name = name.trim()
        ..cost = cost
        ..billingCycle = billingCycle
        ..nextBillingDate = nextBillingDate
        ..category = category
        ..colorHex = colorHex
        ..reminderDaysBefore = reminderDaysBefore
        ..isSynced = false;
      await _database.save(sub);
      return sub;
    });

    if (result case AsyncData<SubscriptionLocal>(:final value)) {
      await _scheduleSafely(value);
    }

    if (!mounted) return !result.hasError;
    state = result.hasError
        ? AsyncError(result.error!, result.stackTrace!)
        : const AsyncData(null);
    return !result.hasError;
  }

  Future<bool> deleteSubscription(String uuid) async {
    final result = await AsyncValue.guard(() async {
      await _notifications.cancelReminder(uuid);
      await _database.delete(uuid);
    });
    if (mounted) state = result;
    return !result.hasError;
  }

  /// Rolls overdue billing dates forward and rebuilds every reminder.
  /// Run on app start and after notification permissions change.
  Future<void> syncSchedules() async {
    try {
      final now = DateTime.now();
      final subs = await _database.getAll();
      await _notifications.cancelAll();

      for (final sub in subs) {
        final rolled = sub.rolledForward(now);
        if (rolled != sub.nextBillingDate) {
          sub
            ..nextBillingDate = rolled
            ..isSynced = false;
          await _database.save(sub);
        }
        await _scheduleSafely(sub);
      }
    } catch (e, st) {
      debugPrint('SubscriptionController.syncSchedules failed: $e\n$st');
    }
  }

  Future<void> _scheduleSafely(SubscriptionLocal sub) async {
    try {
      await _notifications.scheduleRenewalReminder(sub);
    } catch (e, st) {
      debugPrint('Failed to schedule reminder for ${sub.name}: $e\n$st');
    }
  }
}
