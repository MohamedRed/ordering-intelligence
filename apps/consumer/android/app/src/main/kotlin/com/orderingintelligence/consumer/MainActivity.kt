package com.orderingintelligence.consumer

import android.content.Context
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
  private val channelName = "com.orderingintelligence.consumer/session_bridge"
  private val prefsName = "consumer_session"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "saveSession" -> {
            val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
            saveSession(args)
            result.success(true)
          }
          "saveHandoffLink" -> {
            val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
            saveHandoffLink(args["link"] as? String)
            result.success(true)
          }
          "clearSession" -> {
            clearSession()
            result.success(true)
          }
          "loadSession" -> {
            val session = loadSession()
            result.success(session)
          }
          "loadHandoffLink" -> {
            result.success(loadHandoffLink())
          }
          "clearHandoffLink" -> {
            clearHandoffLink()
            result.success(true)
          }
          else -> result.notImplemented()
        }
      }
  }

  private fun sessionPrefs() =
    applicationContext.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

  private fun saveSession(args: Map<*, *>) {
    val editor = sessionPrefs().edit()
    editor.putString("sessionId", args["sessionId"] as? String)
    editor.putString("customerId", args["customerId"] as? String)
    editor.putString("tenantId", args["tenantId"] as? String)
    editor.putString("accountId", args["accountId"] as? String)
    editor.putString("userId", args["userId"] as? String)
    editor.putString("displayName", args["displayName"] as? String)
    editor.putString("storeId", args["storeId"] as? String)
    editor.putString("storeName", args["storeName"] as? String)
    editor.putString("businessType", args["businessType"] as? String)
    editor.putString("currency", args["currency"] as? String)
    val fuelDefault = args["fuelDefaultPrepayCents"]
    when (fuelDefault) {
      is Int -> editor.putInt("fuelDefaultPrepayCents", fuelDefault)
      is Long -> editor.putInt("fuelDefaultPrepayCents", fuelDefault.toInt())
      is String -> editor.putInt("fuelDefaultPrepayCents", fuelDefault.toIntOrNull() ?: 0)
      else -> editor.putInt("fuelDefaultPrepayCents", 0)
    }
    val fuelPreauthCap = args["fuelPreauthCapCents"]
    when (fuelPreauthCap) {
      is Int -> editor.putInt("fuelPreauthCapCents", fuelPreauthCap)
      is Long -> editor.putInt("fuelPreauthCapCents", fuelPreauthCap.toInt())
      is String -> editor.putInt("fuelPreauthCapCents", fuelPreauthCap.toIntOrNull() ?: 0)
      else -> editor.putInt("fuelPreauthCapCents", 0)
    }
    editor.putLong("updatedAt", System.currentTimeMillis())
    editor.apply()
  }

  private fun clearSession() {
    sessionPrefs().edit().clear().apply()
  }

  private fun loadSession(): Map<String, Any?>? {
    val prefs = sessionPrefs()
    val sessionId = prefs.getString("sessionId", null) ?: return null
    return mapOf(
      "sessionId" to sessionId,
      "customerId" to prefs.getString("customerId", null),
      "tenantId" to prefs.getString("tenantId", null),
      "accountId" to prefs.getString("accountId", null),
      "userId" to prefs.getString("userId", null),
      "displayName" to prefs.getString("displayName", null),
      "storeId" to prefs.getString("storeId", null),
      "storeName" to prefs.getString("storeName", null),
      "businessType" to prefs.getString("businessType", null),
      "currency" to prefs.getString("currency", null),
      "fuelDefaultPrepayCents" to prefs.getInt("fuelDefaultPrepayCents", 0),
      "fuelPreauthCapCents" to prefs.getInt("fuelPreauthCapCents", 0),
      "updatedAt" to prefs.getLong("updatedAt", 0L),
    )
  }

  private fun saveHandoffLink(link: String?) {
    val editor = sessionPrefs().edit()
    if (link.isNullOrBlank()) {
      editor.remove("handoffLink")
    } else {
      editor.putString("handoffLink", link)
    }
    editor.apply()
  }

  private fun loadHandoffLink(): String? {
    val link = sessionPrefs().getString("handoffLink", null) ?: return null
    return link.ifBlank { null }
  }

  private fun clearHandoffLink() {
    sessionPrefs().edit().remove("handoffLink").apply()
  }
}
