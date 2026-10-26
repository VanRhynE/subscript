import 'package:isar_community/isar.dart';

part 'subscription_local.g.dart';

/// Allowed values for [SubscriptionLocal.billingCycle].
abstract final class BillingCycle {
  static const String weekly = 'weekly';
  static const String monthly = 'monthly';
  static const String yearly = 'yearly';

  static const List<String> values = [weekly, monthly, yearly];

  static String label(String cycle) => switch (cycle) {
    weekly => 'Weekly',
    yearly => 'Yearly',
    _ => 'Monthly',
  };
}

@collection
class SubscriptionLocal {
  SubscriptionLocal();

  /// Isar's internal auto-increment id. Use [uuid] as the public identity.
  Id id = Isar.autoIncrement;

  /// Stable, globally unique identity (safe for future cloud sync).
  /// Unique + replace => saving an existing uuid updates the row in place.
  @Index(unique: true, replace: true)
  late String uuid;

  late String name;

  late double cost;

  /// One of [BillingCycle.values].
  late String billingCycle;

  late DateTime nextBillingDate;

  late String category;

  /// Accent colour as '#RRGGBB'.
  late String colorHex;

  int reminderDaysBefore = 3;

  /// False until the record has been pushed to a remote backend.
  bool isSynced = false;
}

extension SubscriptionLocalX on SubscriptionLocal {
  /// Cost normalised to a monthly figure.
  double get monthlyCost => switch (billingCycle) {
    BillingCycle.weekly => cost * 52 / 12,
    BillingCycle.yearly => cost / 12,
    _ => cost,
  };

  double get yearlyCost => monthlyCost * 12;

  /// Whole calendar days from [from] until the next billing date.
  int daysUntilBilling([DateTime? from]) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(
      nextBillingDate.year,
      nextBillingDate.month,
      nextBillingDate.day,
    );
    return due.difference(today).inDays;
  }

  /// If [nextBillingDate] is in the past, returns the first billing date on
  /// or after today by stepping whole cycles from the original anchor date
  /// (so month-end dates like the 31st don't drift within a single roll).
  /// Returns the existing [nextBillingDate] untouched when it is not overdue.
  DateTime rolledForward([DateTime? from]) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final anchor = DateTime(
      nextBillingDate.year,
      nextBillingDate.month,
      nextBillingDate.day,
    );
    if (!anchor.isBefore(today)) return nextBillingDate;

    var next = anchor;
    var step = 0;
    while (next.isBefore(today)) {
      step++;
      next = switch (billingCycle) {
        BillingCycle.weekly => DateTime(
          anchor.year,
          anchor.month,
          anchor.day + 7 * step,
        ),
        BillingCycle.yearly => _addMonths(anchor, 12 * step),
        _ => _addMonths(anchor, step),
      };
    }
    return next;
  }
}

DateTime _addMonths(DateTime date, int months) {
  final total = date.month - 1 + months;
  final year = date.year + total ~/ 12;
  final month = total % 12 + 1;
  final lastDayOfMonth = DateTime(year, month + 1, 0).day;
  return DateTime(
    year,
    month,
    date.day > lastDayOfMonth ? lastDayOfMonth : date.day,
  );
}
