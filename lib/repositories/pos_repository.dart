import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/foundation.dart';
import 'package:goldfish_pos/models/appointment_model.dart';
import 'package:goldfish_pos/models/booking_settings_model.dart';
import 'package:goldfish_pos/models/business_settings_model.dart';
import 'package:goldfish_pos/models/cash_drawer_settings_model.dart';
import 'package:goldfish_pos/models/gift_card_model.dart';
import 'package:goldfish_pos/models/item_category_model.dart';
import 'package:goldfish_pos/models/item_model.dart';
import 'package:goldfish_pos/models/employee_model.dart';
import 'package:goldfish_pos/models/customer_model.dart';
import 'package:goldfish_pos/models/payment_method_model.dart';
import 'package:goldfish_pos/models/customer_feedback_model.dart';
import 'package:goldfish_pos/models/reward_settings_model.dart';
import 'package:goldfish_pos/models/sms_settings_model.dart';
import 'package:goldfish_pos/models/transaction_model.dart';

class PosRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== Item Category Operations ====================

  Future<String> createItemCategory(ItemCategory category) async {
    try {
      final docRef = await _firestore
          .collection('itemCategories')
          .add(category.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create category: $e');
    }
  }

  Future<void> updateItemCategory(ItemCategory category) async {
    try {
      await _firestore
          .collection('itemCategories')
          .doc(category.id)
          .update(category.toFirestore());
    } catch (e) {
      throw Exception('Failed to update category: $e');
    }
  }

  Future<void> deleteItemCategory(String categoryId) async {
    try {
      await _firestore.collection('itemCategories').doc(categoryId).delete();
    } catch (e) {
      throw Exception('Failed to delete category: $e');
    }
  }

  Future<ItemCategory?> getItemCategory(String categoryId) async {
    try {
      final doc = await _firestore
          .collection('itemCategories')
          .doc(categoryId)
          .get();
      if (doc.exists) {
        return ItemCategory.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get category: $e');
    }
  }

  Stream<List<ItemCategory>> getItemCategories() {
    return _firestore
        .collection('itemCategories')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ItemCategory.fromFirestore(doc))
              .toList(),
        );
  }

  // ==================== Item Operations ====================

  Future<String> createItem(Item item) async {
    try {
      final docRef = await _firestore
          .collection('items')
          .add(item.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create item: $e');
    }
  }

  Future<void> updateItem(Item item) async {
    try {
      await _firestore
          .collection('items')
          .doc(item.id)
          .update(item.toFirestore());
    } catch (e) {
      throw Exception('Failed to update item: $e');
    }
  }

  Future<void> deleteItem(String itemId) async {
    try {
      await _firestore.collection('items').doc(itemId).delete();
    } catch (e) {
      throw Exception('Failed to delete item: $e');
    }
  }

  Future<Item?> getItem(String itemId) async {
    try {
      final doc = await _firestore.collection('items').doc(itemId).get();
      if (doc.exists) {
        return Item.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get item: $e');
    }
  }

  Stream<List<Item>> getItems() {
    return _firestore
        .collection('items')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Item.fromFirestore(doc)).toList(),
        );
  }

  Stream<List<Item>> getItemsByCategory(String categoryId) {
    return _firestore
        .collection('items')
        .where('categoryId', isEqualTo: categoryId)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Item.fromFirestore(doc)).toList(),
        );
  }

  // ==================== Employee Operations ====================

  Future<String> createEmployee(Employee employee) async {
    try {
      final docRef = await _firestore
          .collection('employees')
          .add(employee.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create employee: $e');
    }
  }

  Future<void> updateEmployee(Employee employee) async {
    try {
      await _firestore
          .collection('employees')
          .doc(employee.id)
          .update(employee.toFirestore());
    } catch (e) {
      throw Exception('Failed to update employee: $e');
    }
  }

  Future<void> deleteEmployee(String employeeId) async {
    try {
      await _firestore.collection('employees').doc(employeeId).delete();
    } catch (e) {
      throw Exception('Failed to delete employee: $e');
    }
  }

  Future<Employee?> getEmployee(String employeeId) async {
    try {
      final doc = await _firestore
          .collection('employees')
          .doc(employeeId)
          .get();
      if (doc.exists) {
        return Employee.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get employee: $e');
    }
  }

  Stream<List<Employee>> getEmployees() {
    return _firestore
        .collection('employees')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Employee.fromFirestore(doc)).toList(),
        );
  }

  // ==================== Customer Operations ====================

  Future<String> createCustomer(Customer customer) async {
    try {
      final docRef = await _firestore
          .collection('customers')
          .add(customer.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create customer: $e');
    }
  }

  Future<void> updateCustomer(Customer customer) async {
    try {
      await _firestore
          .collection('customers')
          .doc(customer.id)
          .update(customer.toFirestore());
    } catch (e) {
      throw Exception('Failed to update customer: $e');
    }
  }

  Future<void> deleteCustomer(String customerId) async {
    try {
      await _firestore.collection('customers').doc(customerId).delete();
    } catch (e) {
      throw Exception('Failed to delete customer: $e');
    }
  }

  Future<Customer?> getCustomer(String customerId) async {
    try {
      final doc = await _firestore
          .collection('customers')
          .doc(customerId)
          .get();
      if (doc.exists) {
        return Customer.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get customer: $e');
    }
  }

  Stream<List<Customer>> getCustomers() {
    return _firestore
        .collection('customers')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Customer.fromFirestore(doc)).toList(),
        );
  }

  /// Fetches ALL customers (active and inactive) for reporting purposes.
  Future<List<Customer>> getAllCustomers() async {
    final snapshot = await _firestore.collection('customers').get();
    return snapshot.docs.map((doc) => Customer.fromFirestore(doc)).toList();
  }

  /// Looks up an active customer by phone number (exact match).
  /// Returns null if no match is found.
  Future<Customer?> getCustomerByPhone(String phone) async {
    try {
      final snapshot = await _firestore
          .collection('customers')
          .where('phone', isEqualTo: phone)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return null;
      return Customer.fromFirestore(snapshot.docs.first);
    } catch (e) {
      throw Exception('Failed to look up customer by phone: $e');
    }
  }

  // ==================== Payment Method Operations ====================

  Future<String> createPaymentMethod(PaymentMethod paymentMethod) async {
    try {
      final docRef = await _firestore
          .collection('paymentMethods')
          .add(paymentMethod.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create payment method: $e');
    }
  }

  Future<void> updatePaymentMethod(PaymentMethod paymentMethod) async {
    try {
      await _firestore
          .collection('paymentMethods')
          .doc(paymentMethod.id)
          .update(paymentMethod.toFirestore());
    } catch (e) {
      throw Exception('Failed to update payment method: $e');
    }
  }

  Future<void> deletePaymentMethod(String paymentMethodId) async {
    try {
      await _firestore
          .collection('paymentMethods')
          .doc(paymentMethodId)
          .delete();
    } catch (e) {
      throw Exception('Failed to delete payment method: $e');
    }
  }

  Future<PaymentMethod?> getPaymentMethod(String paymentMethodId) async {
    try {
      final doc = await _firestore
          .collection('paymentMethods')
          .doc(paymentMethodId)
          .get();
      if (doc.exists) {
        return PaymentMethod.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get payment method: $e');
    }
  }

  Stream<List<PaymentMethod>> getPaymentMethods() {
    return _firestore
        .collection('paymentMethods')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PaymentMethod.fromFirestore(doc))
              .toList(),
        );
  }

  // ==================== Transaction Operations ====================

  Future<String> createTransaction(Transaction transaction) async {
    try {
      // Count today's transactions to assign a sequential daily number.
      final now = DateTime.now();
      final startOfDay = Timestamp.fromDate(
        DateTime(now.year, now.month, now.day, 0, 0, 0),
      );
      final endOfDay = Timestamp.fromDate(
        DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
      final todaySnap = await _firestore
          .collection('transactions')
          .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
          .where('createdAt', isLessThanOrEqualTo: endOfDay)
          .count()
          .get();
      final dailyNumber = (todaySnap.count ?? 0) + 1;

      final data = transaction.toFirestore();
      data['dailyNumber'] = dailyNumber;

      final docRef = await _firestore.collection('transactions').add(data);
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create transaction: $e');
    }
  }

  Future<void> updateTransaction(Transaction transaction) async {
    try {
      await _firestore
          .collection('transactions')
          .doc(transaction.id)
          .update(transaction.toFirestore());
    } catch (e) {
      throw Exception('Failed to update transaction: $e');
    }
  }

  Future<void> deleteTransaction(String transactionId) async {
    try {
      await _firestore.collection('transactions').doc(transactionId).delete();
    } catch (e) {
      throw Exception('Failed to delete transaction: $e');
    }
  }

  Future<Transaction?> getTransaction(String transactionId) async {
    try {
      final doc = await _firestore
          .collection('transactions')
          .doc(transactionId)
          .get();
      if (doc.exists) {
        return Transaction.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get transaction: $e');
    }
  }

  Stream<List<Transaction>> getTransactions() {
    return _firestore
        .collection('transactions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Transaction.fromFirestore(doc))
              .toList(),
        );
  }

  Stream<List<Transaction>> getTransactionsByCustomer(String customerId) {
    return _firestore
        .collection('transactions')
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Transaction.fromFirestore(doc))
              .toList(),
        );
  }

  Stream<List<Transaction>> getTransactionsByEmployee(String employeeId) {
    return _firestore
        .collection('transactions')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Transaction.fromFirestore(doc))
              .where(
                (transaction) => transaction.employeeIds.contains(employeeId),
              )
              .toList(),
        );
  }

  Stream<List<Transaction>> getTransactionsByStatus(String status) {
    return _firestore
        .collection('transactions')
        .where('status', isEqualTo: status)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => Transaction.fromFirestore(doc))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  // Get non-voided transactions for reporting
  Stream<List<Transaction>> getActiveTransactions() {
    return _firestore
        .collection('transactions')
        .where('isVoided', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Transaction.fromFirestore(doc))
              .toList(),
        );
  }

  /// Returns transactions whose createdAt falls within [start, end] (inclusive).
  /// Voided transactions are excluded by default; pass [includeVoided] = true
  /// to include them.
  Future<List<Transaction>> getTransactionsByDateRange(
    DateTime start,
    DateTime end, {
    bool includeVoided = false,
  }) async {
    final from = Timestamp.fromDate(
      DateTime(start.year, start.month, start.day, 0, 0, 0),
    );
    final to = Timestamp.fromDate(
      DateTime(end.year, end.month, end.day, 23, 59, 59),
    );
    final snapshot = await _firestore
        .collection('transactions')
        .where('createdAt', isGreaterThanOrEqualTo: from)
        .where('createdAt', isLessThanOrEqualTo: to)
        .get();
    final txns = snapshot.docs
        .map((doc) => Transaction.fromFirestore(doc))
        .where((tx) => includeVoided || tx.status != TransactionStatus.voided)
        .toList();
    // Sort by createdAt ascending (avoids needing a Firestore composite index)
    txns.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return txns;
  }

  // ==================== Helper Methods ====================

  // Void a transaction
  Future<void> voidTransaction(String transactionId) async {
    try {
      await _firestore.collection('transactions').doc(transactionId).update({
        'isVoided': true,
        'status': 'voided',
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Failed to void transaction: $e');
    }
  }

  // Add payment to transaction
  Future<void> addPaymentToTransaction(
    String transactionId,
    Payment payment,
  ) async {
    try {
      await _firestore.collection('transactions').doc(transactionId).update({
        'payments': FieldValue.arrayUnion([payment.toJson()]),
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Failed to add payment: $e');
    }
  }

  // Add discount to transaction
  Future<void> addDiscountToTransaction(
    String transactionId,
    Discount discount,
  ) async {
    try {
      await _firestore.collection('transactions').doc(transactionId).update({
        'discounts': FieldValue.arrayUnion([discount.toJson()]),
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Failed to add discount: $e');
    }
  }

  // ==================== Reward Settings ====================

  Future<RewardSettings> getRewardSettings() async {
    try {
      final doc = await _firestore
          .collection('settings')
          .doc('rewardProgram')
          .get();
      if (doc.exists) return RewardSettings.fromFirestore(doc);
      return const RewardSettings(); // defaults
    } catch (e) {
      throw Exception('Failed to get reward settings: $e');
    }
  }

  Future<void> updateRewardSettings(RewardSettings settings) async {
    try {
      await _firestore
          .collection('settings')
          .doc('rewardProgram')
          .set(settings.toFirestore());
    } catch (e) {
      throw Exception('Failed to update reward settings: $e');
    }
  }

  /// Atomically adjusts a customer's reward points (positive to add, negative to redeem).
  Future<void> adjustCustomerPoints(String customerId, double delta) async {
    try {
      await _firestore.collection('customers').doc(customerId).update({
        'rewardPoints': FieldValue.increment(delta),
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Failed to adjust customer points: $e');
    }
  }

  // ==================== Cash Drawer Settings ====================

  Future<CashDrawerSettings> getCashDrawerSettings() async {
    try {
      final doc = await _firestore
          .collection('settings')
          .doc('cashDrawer')
          .get();
      if (doc.exists) return CashDrawerSettings.fromFirestore(doc);
      return const CashDrawerSettings();
    } catch (e) {
      throw Exception('Failed to get cash drawer settings: $e');
    }
  }

  Future<void> saveCashDrawerSettings(CashDrawerSettings settings) async {
    try {
      await _firestore
          .collection('settings')
          .doc('cashDrawer')
          .set(settings.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to save cash drawer settings: $e');
    }
  }

  // ==================== Appointment Operations ====================

  Future<String> createAppointment(Appointment appt) async {
    try {
      final docRef = await _firestore
          .collection('appointments')
          .add(appt.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create appointment: $e');
    }
  }

  Future<void> updateAppointment(Appointment appt) async {
    try {
      await _firestore.collection('appointments').doc(appt.id).update({
        ...appt.toFirestore(),
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Failed to update appointment: $e');
    }
  }

  Future<void> deleteAppointment(String id) async {
    try {
      await _firestore.collection('appointments').doc(id).delete();
    } catch (e) {
      throw Exception('Failed to delete appointment: $e');
    }
  }

  /// Stream of all appointments scheduled for [date] (midnight–midnight).
  Stream<List<Appointment>> getAppointmentsForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return _firestore
        .collection('appointments')
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('scheduledAt')
        .snapshots()
        .map((s) {
          final results = <Appointment>[];
          for (final doc in s.docs) {
            try {
              results.add(Appointment.fromFirestore(doc));
            } catch (e) {
              debugPrint('Skipping malformed appointment doc ${doc.id}: $e');
            }
          }
          return results;
        });
  }

  /// Stream of appointments for a date range (inclusive).
  Stream<List<Appointment>> getAppointmentsInRange(DateTime from, DateTime to) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(
      to.year,
      to.month,
      to.day,
    ).add(const Duration(days: 1));
    return _firestore
        .collection('appointments')
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('scheduledAt')
        .snapshots()
        .map((s) => s.docs.map(Appointment.fromFirestore).toList());
  }

  Future<void> updateAppointmentStatus(
    String id,
    AppointmentStatus status,
  ) async {
    try {
      await _firestore.collection('appointments').doc(id).update({
        'status': status.name,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Failed to update appointment status: $e');
    }
  }

  // ==================== Booking Settings ====================

  Future<BookingSettings> getBookingSettings() async {
    try {
      final doc = await _firestore.collection('settings').doc('booking').get();
      if (doc.exists) return BookingSettings.fromFirestore(doc);
      return BookingSettings.defaults;
    } catch (e) {
      throw Exception('Failed to get booking settings: $e');
    }
  }

  Stream<BookingSettings> streamBookingSettings() {
    return _firestore
        .collection('settings')
        .doc('booking')
        .snapshots()
        .map(
          (doc) => doc.exists
              ? BookingSettings.fromFirestore(doc)
              : BookingSettings.defaults,
        );
  }

  Future<void> saveBookingSettings(BookingSettings settings) async {
    try {
      await _firestore
          .collection('settings')
          .doc('booking')
          .set(settings.toFirestore());
    } catch (e) {
      throw Exception('Failed to save booking settings: $e');
    }
  }

  // ==================== SMS Settings ====================

  Future<SmsSettings> getSmsSettings() async {
    try {
      final doc = await _firestore.collection('settings').doc('sms').get();
      if (doc.exists) return SmsSettings.fromFirestore(doc);
      return const SmsSettings();
    } catch (e) {
      throw Exception('Failed to get SMS settings: $e');
    }
  }

  Future<void> saveSmsSettings(SmsSettings settings) async {
    try {
      await _firestore
          .collection('settings')
          .doc('sms')
          .set(settings.toFirestore());
    } catch (e) {
      throw Exception('Failed to save SMS settings: $e');
    }
  }

  // ==================== Customer Feedback ====================

  Future<String> saveCustomerFeedback(CustomerFeedback feedback) async {
    try {
      final docRef = await _firestore
          .collection('customerFeedback')
          .add(feedback.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to save customer feedback: $e');
    }
  }

  Stream<List<CustomerFeedback>> streamCustomerFeedback() {
    return _firestore
        .collection('customerFeedback')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => CustomerFeedback.fromFirestore(doc))
              .toList(),
        );
  }

  Future<void> deleteCustomerFeedback(String feedbackId) async {
    try {
      await _firestore.collection('customerFeedback').doc(feedbackId).delete();
    } catch (e) {
      throw Exception('Failed to delete feedback: $e');
    }
  }

  /// Saves only public SMS fields (enable, templates, reviewUrl) using merge
  /// so that Twilio credentials stored by System Admin are never overwritten.
  Future<void> saveSmsPublicSettings(SmsSettings settings) async {
    try {
      await _firestore.collection('settings').doc('sms').set({
        'enabled': settings.enabled,
        'positiveTemplate': settings.positiveTemplate,
        'negativeTemplate': settings.negativeTemplate,
        'googleReviewUrl': settings.googleReviewUrl,
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to save SMS settings: $e');
    }
  }

  /// Saves only Twilio credentials using merge (System Admin only).
  Future<void> saveTwilioCredentials({
    required String accountSid,
    required String authToken,
    required String fromNumber,
  }) async {
    try {
      await _firestore.collection('settings').doc('sms').set({
        'accountSid': accountSid,
        'authToken': authToken,
        'fromNumber': fromNumber,
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to save Twilio credentials: $e');
    }
  }

  // ==================== System Admin PIN ====================

  /// Default PIN used when none has been set yet.
  static const String _defaultPin = '0000';

  /// Retrieves the System Admin PIN from Firestore.
  /// Returns '0000' if not yet configured.
  Future<String> getSysAdminPin() async {
    try {
      final doc = await _firestore
          .collection('settings')
          .doc('systemAdmin')
          .get();
      return (doc.data()?['pin'] as String?) ?? _defaultPin;
    } catch (e) {
      return _defaultPin;
    }
  }

  /// Saves a new System Admin PIN.
  Future<void> saveSysAdminPin(String pin) async {
    try {
      await _firestore.collection('settings').doc('systemAdmin').set({
        'pin': pin,
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to save PIN: $e');
    }
  }

  // ==================== Admin PIN ====================

  /// Default admin PIN used when none has been set yet.
  static const String _defaultAdminPin = '1234';

  /// Retrieves the Admin (Setup screen) PIN from Firestore.
  /// Returns '1234' if not yet configured.
  Future<String> getAdminPin() async {
    try {
      final doc = await _firestore.collection('settings').doc('admin').get();
      return (doc.data()?['pin'] as String?) ?? _defaultAdminPin;
    } catch (e) {
      return _defaultAdminPin;
    }
  }

  /// Saves a new Admin PIN.
  Future<void> saveAdminPin(String pin) async {
    try {
      await _firestore.collection('settings').doc('admin').set({
        'pin': pin,
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to save admin PIN: $e');
    }
  }

  // ==================== Business Settings ====================

  /// Returns the salon's business information (name, address, phone, tax).
  Future<BusinessSettings> getBusinessSettings() async {
    try {
      final doc = await _firestore.collection('settings').doc('business').get();
      if (doc.exists) return BusinessSettings.fromFirestore(doc);
      return const BusinessSettings();
    } catch (e) {
      return const BusinessSettings();
    }
  }

  /// Saves (merges) business settings to Firestore.
  Future<void> saveBusinessSettings(BusinessSettings settings) async {
    try {
      await _firestore
          .collection('settings')
          .doc('business')
          .set(settings.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to save business settings: $e');
    }
  }

  // ==================== Gift Card Operations ====================

  /// Creates a new gift card document and returns its Firestore ID.
  Future<String> createGiftCard(GiftCard card) async {
    try {
      final docRef = await _firestore
          .collection('giftCards')
          .add(card.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create gift card: $e');
    }
  }

  /// Updates an existing gift card document (full overwrite of mutable fields).
  Future<void> updateGiftCard(GiftCard card) async {
    try {
      await _firestore
          .collection('giftCards')
          .doc(card.id)
          .update(card.toFirestore());
    } catch (e) {
      throw Exception('Failed to update gift card: $e');
    }
  }

  /// Looks up a gift card by its human-readable [cardId] label.
  /// Returns null if no matching card is found.
  Future<GiftCard?> getGiftCardByCardId(String cardId) async {
    try {
      final snapshot = await _firestore
          .collection('giftCards')
          .where('cardId', isEqualTo: cardId.trim())
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return null;
      return GiftCard.fromFirestore(snapshot.docs.first);
    } catch (e) {
      throw Exception('Failed to look up gift card: $e');
    }
  }

  /// Streams all gift cards ordered by issue date (most recent first).
  Stream<List<GiftCard>> streamGiftCards() {
    return _firestore
        .collection('giftCards')
        .orderBy('issuedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => GiftCard.fromFirestore(doc)).toList(),
        );
  }

  /// Atomically deducts [amount] from a gift card's balance and appends a
  /// ledger entry. Throws if the card doesn't have sufficient balance.
  Future<void> deductFromGiftCard(
    String giftCardDocId,
    double amount, {
    String? transactionId,
    String? note,
  }) async {
    try {
      await _firestore.runTransaction((txn) async {
        final ref = _firestore.collection('giftCards').doc(giftCardDocId);
        final snap = await txn.get(ref);
        if (!snap.exists) throw Exception('Gift card not found.');

        final current = GiftCard.fromFirestore(snap);
        if (current.balance < amount - 0.001) {
          throw Exception(
            'Insufficient gift card balance '
            '(\$${current.balance.toStringAsFixed(2)} available).',
          );
        }

        final entry = GiftCardEntry(
          type: GiftCardEntryType.redeemed,
          amount: -amount,
          date: DateTime.now(),
          transactionId: transactionId,
          note: note,
        );

        final newBalance = (current.balance - amount).clamp(
          0.0,
          double.infinity,
        );
        final updatedHistory = [...current.history, entry];

        txn.update(ref, {
          'balance': newBalance,
          'history': updatedHistory.map((e) => e.toJson()).toList(),
          'updatedAt': Timestamp.now(),
        });
      });
    } catch (e) {
      throw Exception('Failed to deduct from gift card: $e');
    }
  }

  /// Adds [amount] to a gift card's balance (reload / top-up). This also
  /// reactivates a previously deactivated card.
  Future<void> reloadGiftCard(
    String giftCardDocId,
    double amount, {
    String? note,
  }) async {
    try {
      await _firestore.runTransaction((txn) async {
        final ref = _firestore.collection('giftCards').doc(giftCardDocId);
        final snap = await txn.get(ref);
        if (!snap.exists) throw Exception('Gift card not found.');

        final current = GiftCard.fromFirestore(snap);

        final entry = GiftCardEntry(
          type: GiftCardEntryType.reloaded,
          amount: amount,
          date: DateTime.now(),
          note: note,
        );

        final updatedHistory = [...current.history, entry];

        txn.update(ref, {
          'balance': current.balance + amount,
          'loadedAmount': amount,
          'isActive': true, // reactivate if it was deactivated
          'history': updatedHistory.map((e) => e.toJson()).toList(),
          'updatedAt': Timestamp.now(),
        });
      });
    } catch (e) {
      throw Exception('Failed to reload gift card: $e');
    }
  }

  /// Deactivates a gift card (sets isActive = false).
  Future<void> deactivateGiftCard(String giftCardDocId) async {
    try {
      await _firestore.collection('giftCards').doc(giftCardDocId).update({
        'isActive': false,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Failed to deactivate gift card: $e');
    }
  }

  /// Reactivates a previously deactivated gift card.
  Future<void> reactivateGiftCard(String giftCardDocId) async {
    try {
      await _firestore.collection('giftCards').doc(giftCardDocId).update({
        'isActive': true,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Failed to reactivate gift card: $e');
    }
  }

  /// Adds a gift card sale as a line item to an existing transaction and
  /// updates the transaction subtotal and totalAmount by [amount].
  /// Gift cards are not taxed — only the sale amount is added.
  Future<void> addGiftCardSaleToTransaction(
    String transactionId,
    TransactionItem item,
    double amount,
  ) async {
    try {
      final ref = _firestore.collection('transactions').doc(transactionId);
      await _firestore.runTransaction((txn) async {
        final snap = await txn.get(ref);
        if (!snap.exists) throw Exception('Transaction not found.');
        final data = snap.data()!;

        final currentItems = List<Map<String, dynamic>>.from(
          (data['items'] as List<dynamic>? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        currentItems.add(item.toJson());

        final newSubtotal = (data['subtotal'] ?? 0).toDouble() + amount;
        final newTotal = (data['totalAmount'] ?? 0).toDouble() + amount;

        txn.update(ref, {
          'items': currentItems,
          'subtotal': newSubtotal,
          'totalAmount': newTotal,
          'updatedAt': Timestamp.now(),
        });
      });
    } catch (e) {
      throw Exception('Failed to add gift card sale to transaction: $e');
    }
  }
}
