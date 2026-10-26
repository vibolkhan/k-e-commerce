/// Statuses shown to people across the apps. Values follow the Components
/// board and App Flow v1.0; the server owns transitions, the client only
/// displays them. Features extend these when they land.
library;

enum OrderStatus {
  pendingPayment,
  awaitingBankTransfer,
  confirmed,
  packing,
  ready,
  outForDelivery,
  delivered,
  failedDelivery,
  cancelled,
  returned,
}

enum PaymentStatus {
  paid,
  waitingForKhqr,
  awaitingConfirmation,
  cashOnDelivery,
  expired,
  slipRejected,
  refunded,
}

/// Quote request (RFQ) status.
enum QuoteStatus {
  submitted,
  inReview,
  quoteReady,
  revisionRequested,
  accepted,
  rejected,
  expired,
}

enum ReturnStatus { requested, pickupScheduled, refunded }

enum BusinessVerificationStatus { pending, verified }

enum ReviewStatus { pending, hidden }

enum RiderJobStatus { assigned, returnPickup }
