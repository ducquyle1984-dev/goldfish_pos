import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:goldfish_pos/models/item_category_model.dart';
import 'package:goldfish_pos/models/item_model.dart';
import 'package:goldfish_pos/models/employee_model.dart';
import 'package:goldfish_pos/models/customer_model.dart';
import 'package:goldfish_pos/models/payment_method_model.dart';
import 'package:goldfish_pos/models/reward_settings_model.dart';
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
}
