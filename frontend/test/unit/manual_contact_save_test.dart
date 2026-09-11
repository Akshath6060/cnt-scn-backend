import 'package:contact_scanner/providers/review_provider.dart';
import 'package:contact_scanner/services/contact_service.dart';
import 'package:contact_scanner/services/duplicate_detection_service.dart';
import 'package:contact_scanner/services/phone_number_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_contacts_gateway.dart';

void main() {
  test(
    'a manually entered contact is saved to the device phonebook gateway',
    () async {
      final gateway = FakeContactsGateway();
      final notifier = ReviewNotifier(
        contacts: ContactService(gateway: gateway),
        duplicates: const DuplicateDetectionService(),
        phoneParser: const PhoneNumberParser(),
        registerTemporary: (_) async {},
      );

      notifier.addManualContact(name: 'Anu', phone: '98765 43210');

      expect(notifier.state.contacts, hasLength(1));
      expect(notifier.state.selectedCount, 1);
      expect(notifier.state.contacts.single.phoneForSaving, '+919876543210');

      final summary = await notifier.save();

      expect(summary.saved, 1);
      expect(gateway.store.values.single.displayName, 'Anu');
      expect(gateway.store.values.single.phones, ['+919876543210']);
    },
  );
}
