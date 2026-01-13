package com.orderingintelligence.auto

import android.content.Context

class AutoSessionStore(private val context: Context) {
  private fun prefs() = context.getSharedPreferences("consumer_session", Context.MODE_PRIVATE)

  fun sessionId(): String? {
    return prefs().getString("sessionId", null)
  }

  fun saveHandoffLink(link: String) {
    prefs().edit().putString("handoffLink", link).apply()
  }
}
