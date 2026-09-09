package com.example.contact_scanner

import android.accounts.AccountManager
import android.content.ContentProviderOperation
import android.content.Intent
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.contact_scanner/contacts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "insertContact" -> {
                        val firstName = call.argument<String>("firstName") ?: ""
                        val lastName = call.argument<String>("lastName") ?: ""
                        val phone = call.argument<String>("phone") ?: ""
                        try {
                            insertContact(firstName, lastName, phone)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSERT_FAILED", e.message, null)
                        }
                    }
                    "openContactsApp" -> {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW)
                            intent.data = ContactsContract.Contacts.CONTENT_URI
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_FAILED", e.message, null)
                        }
                    }
                    "checkContactExists" -> {
                        val name = call.argument<String>("name") ?: ""
                        try {
                            val exists = checkContactExists(name)
                            result.success(exists)
                        } catch (e: Exception) {
                            result.error("CHECK_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Checks if a contact with the given name already exists in the device contacts.
     */
    private fun checkContactExists(name: String): Boolean {
        if (name.isEmpty()) return false
        val uri = ContactsContract.Contacts.CONTENT_URI
        val projection = arrayOf(ContactsContract.Contacts.DISPLAY_NAME)
        val selection = "${ContactsContract.Contacts.DISPLAY_NAME} = ?"
        val selectionArgs = arrayOf(name)

        contentResolver.query(uri, projection, selection, selectionArgs, null)?.use { cursor ->
            if (cursor.count > 0) {
                return true
            }
        }
        return false
    }

    /**
     * Inserts a contact using the Android ContactsContract API.
     *
     * Detects the default Google account (if any) and inserts under that
     * account so the contact syncs to the cloud. Falls back to local
     * account (null) if no Google account is found.
     *
     * This avoids the "Cannot add contacts to local or SIM accounts
     * when default account is set to cloud" crash that occurs on devices
     * where the default contacts account is a cloud account.
     */
    private fun insertContact(firstName: String, lastName: String, phone: String) {
        // Find a Google account to insert under.
        val accountManager = AccountManager.get(this)
        val googleAccounts = accountManager.getAccountsByType("com.google")

        val accountName: String? = googleAccounts.firstOrNull()?.name
        val accountType: String? = if (accountName != null) "com.google" else null

        val ops = ArrayList<ContentProviderOperation>()

        // 1. Insert a new raw contact with the correct account.
        ops.add(
            ContentProviderOperation.newInsert(ContactsContract.RawContacts.CONTENT_URI)
                .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, accountType)
                .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, accountName)
                .build()
        )

        // 2. Set the display name (structured name).
        ops.add(
            ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(
                    ContactsContract.Data.MIMETYPE,
                    ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE
                )
                .withValue(ContactsContract.CommonDataKinds.StructuredName.GIVEN_NAME, firstName)
                .withValue(ContactsContract.CommonDataKinds.StructuredName.FAMILY_NAME, lastName)
                .build()
        )

        // 3. Add the phone number.
        if (phone.isNotEmpty()) {
            ops.add(
                ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                    .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                    .withValue(
                        ContactsContract.Data.MIMETYPE,
                        ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE
                    )
                    .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, phone)
                    .withValue(
                        ContactsContract.CommonDataKinds.Phone.TYPE,
                        ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE
                    )
                    .build()
            )
        }

        contentResolver.applyBatch(ContactsContract.AUTHORITY, ops)
    }
}
