import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/time/date_format.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/inventory.dart';

/// The A-06 / A-06a status pill: Out, Low, OK, Not stocked.
(String, KTone) statePill(AppLocalizations l10n, InventoryState state) =>
    switch (state) {
      InventoryState.out => (l10n.catalogStockOutShort, KTone.red),
      InventoryState.low => (l10n.catalogStockLowShort, KTone.amber),
      InventoryState.ok => (l10n.catalogStockOk, KTone.green),
      InventoryState.none => (l10n.catalogNotStocked, KTone.gray),
    };

String filterLabel(AppLocalizations l10n, InventoryFilter filter) =>
    switch (filter) {
      InventoryFilter.restock => l10n.inventoryFilterRestock,
      InventoryFilter.out => l10n.inventoryFilterOut,
      InventoryFilter.all => l10n.inventoryFilterAll,
    };

String ledgerLabel(AppLocalizations l10n, StockReason reason) =>
    switch (reason) {
      StockReason.received => l10n.inventoryLedgerReceived,
      StockReason.adjustment => l10n.inventoryLedgerAdjustment,
      StockReason.damaged => l10n.inventoryLedgerDamaged,
      StockReason.reserved => l10n.inventoryLedgerReserved,
      StockReason.released => l10n.inventoryLedgerReleased,
      StockReason.sold => l10n.inventoryLedgerSold,
      StockReason.returned => l10n.inventoryLedgerReturned,
    };

String modeLabel(AppLocalizations l10n, AdjustMode mode) => switch (mode) {
  AdjustMode.add => l10n.inventoryModeAdd,
  AdjustMode.remove => l10n.inventoryModeRemove,
  AdjustMode.set => l10n.inventoryModeSet,
};

String modeHelp(AppLocalizations l10n, AdjustMode mode) => switch (mode) {
  AdjustMode.add => l10n.inventoryModeAddHelp,
  AdjustMode.remove => l10n.inventoryModeRemoveHelp,
  AdjustMode.set => l10n.inventoryModeSetHelp,
};

String qtyLabel(AppLocalizations l10n, AdjustMode mode) => switch (mode) {
  AdjustMode.add => l10n.inventoryQtyAdd,
  AdjustMode.remove => l10n.inventoryQtyRemove,
  AdjustMode.set => l10n.inventoryQtySet,
};

String reasonLabel(AppLocalizations l10n, AdjustReason reason) =>
    switch (reason) {
      AdjustReason.receivedFromSupplier =>
        l10n.inventoryReasonReceivedFromSupplier,
      AdjustReason.returnedToStock => l10n.inventoryReasonReturnedToStock,
      AdjustReason.damaged => l10n.inventoryReasonDamaged,
      AdjustReason.lost => l10n.inventoryReasonLost,
      AdjustReason.usedInStore => l10n.inventoryReasonUsed,
      AdjustReason.countCorrection => l10n.inventoryReasonCountCorrection,
    };

/// "+50", "−2" (a real minus sign).
String signed(int delta) => delta > 0 ? '+$delta' : '−${delta.abs()}';

/// "Sold −2", "Received +50".
String changeLabel(AppLocalizations l10n, StockReason reason, int delta) =>
    l10n.inventoryChange(ledgerLabel(l10n, reason), signed(delta));

/// "21 Oct, 5:02 PM".
String whenLabel(AppLocalizations l10n, DateTime at) =>
    l10n.inventoryWhen(formatDayMonth(l10n, at), formatTime(l10n, at));

/// "21 Oct, 5:02 PM · Visal Keo" or "… · Order K-10253".
String whoLabel(
  AppLocalizations l10n, {
  required DateTime? at,
  String? actor,
  String? orderNumber,
}) {
  final when = at == null ? '' : whenLabel(l10n, at);
  final who =
      actor ??
      (orderNumber == null ? null : l10n.inventoryOrderRef(orderNumber));
  if (who == null) return when;
  if (when.isEmpty) return who;
  return l10n.inventoryByWho(when, who);
}

String outcomeMessage(AppLocalizations l10n, InventoryOutcome outcome) =>
    switch (outcome) {
      StockAdjusted() => '',
      StockBelowReserved(:final reserved) => l10n.inventoryErrBelowReserved(
        reserved,
      ),
      InventoryRefused(reason: InventoryRefusal.forbidden) =>
        l10n.inventoryErrForbidden,
      InventoryRefused(reason: InventoryRefusal.notFound) =>
        l10n.inventoryErrNotFound,
      InventoryRefused(reason: InventoryRefusal.invalid) =>
        l10n.inventoryErrInvalid,
      InventoryRefused(reason: InventoryRefusal.unknown) =>
        l10n.inventoryErrUnknown,
    };
