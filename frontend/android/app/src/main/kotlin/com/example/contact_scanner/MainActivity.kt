package com.example.contact_scanner

import android.content.ContentProviderOperation
import android.content.Intent
import android.os.Build
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
                        val name = call.argument<String>("name") ?: ""
                        val phone = call.argument<String>("phone") ?: ""
                        try {
                            result.success(insertContact(name, phone))
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
    private fun insertContact(name: String, phone: String): String {
        // Android 13+ exposes the account selected by the user in their
        // default Contacts app. Using it is essential on devices that reject
        // local inserts while a cloud account is configured as the default.
        val defaultAccount = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            @Suppress("DEPRECATION")
            ContactsContract.Settings.getDefaultAccount(contentResolver)
        } else {
            null
        }
        val accountName = defaultAccount?.name
        val accountType = defaultAccount?.type

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
                .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, name)
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

        val results = contentResolver.applyBatch(ContactsContract.AUTHORITY, ops)
        val rawContactUri = results.firstOrNull()?.uri
            ?: throw IllegalStateException("Contacts provider returned no contact URI")

        contentResolver.query(
            rawContactUri,
            arrayOf(ContactsContract.RawContacts.CONTACT_ID),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getLong(0).toString()
            }
        }
        throw IllegalStateException("Contacts provider returned no aggregate contact ID")
    }
}
