import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/subscription_local.dart';

/// Owns the Isar instance and exposes all subscription persistence.
class DatabaseService {
  Isar? _isar;
  Future<void>? _opening;

  Isar get _db {
    final isar = _isar;
    if (isar == null) {
      throw StateError('DatabaseService.init() must complete before use.');
    }
    return isar;
  }

  /// Idempotent: safe to call more than once.
  Future<void> init() => _opening ??= _open();

  Future<void> _open() async {
    if (Isar.instanceNames.contains('subscript')) {
      _isar = Isar.getInstance('subscript');
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [SubscriptionLocalSchema],
      directory: dir.path,
      name: 'subscript',
    );
  }

  /// Insert or update (matched on [SubscriptionLocal.uuid]).
  Future<void> save(SubscriptionLocal subscription) async {
    await _db.writeTxn(() => _db.subscriptionLocals.putByUuid(subscription));
  }

  Future<void> saveAll(List<SubscriptionLocal> subscriptions) async {
    await _db.writeTxn(
      () => _db.subscriptionLocals.putAllByUuid(subscriptions),
    );
  }

  Future<List<SubscriptionLocal>> getAll() {
    return _db.subscriptionLocals.where().sortByNextBillingDate().findAll();
  }

  Future<SubscriptionLocal?> getByUuid(String uuid) {
    return _db.subscriptionLocals.getByUuid(uuid);
  }

  /// Emits the full list (soonest renewal first) now and on every change.
  Stream<List<SubscriptionLocal>> watchAll() {
    return _db.subscriptionLocals.where().sortByNextBillingDate().watch(
      fireImmediately: true,
    );
  }

  /// Returns true if a record was removed.
  Future<bool> delete(String uuid) {
    return _db.writeTxn(() => _db.subscriptionLocals.deleteByUuid(uuid));
  }

  Future<void> close() async {
    await _isar?.close();
    _isar = null;
    _opening = null;
  }
}
