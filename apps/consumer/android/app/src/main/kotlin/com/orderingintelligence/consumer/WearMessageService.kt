package com.orderingintelligence.consumer

import android.content.Context
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import java.nio.charset.StandardCharsets

class WearMessageService : WearableListenerService() {
  override fun onMessageReceived(event: MessageEvent) {
    when (event.path) {
      "/session/request" -> respondWithSession(event)
      "/handoff" -> handleHandoff(event)
      else -> super.onMessageReceived(event)
    }
  }

  private fun respondWithSession(event: MessageEvent) {
    val sessionId = sessionPrefs().getString("sessionId", "") ?: ""
    if (sessionId.isEmpty()) return
    val payload = sessionId.toByteArray(StandardCharsets.UTF_8)
    Wearable.getMessageClient(this)
      .sendMessage(event.sourceNodeId, "/session/response", payload)
  }

  private fun handleHandoff(event: MessageEvent) {
    val link = event.data?.toString(StandardCharsets.UTF_8) ?: ""
    if (link.isBlank()) return
    sessionPrefs().edit().putString("handoffLink", link).apply()
  }

  private fun sessionPrefs() =
    applicationContext.getSharedPreferences("consumer_session", Context.MODE_PRIVATE)
}
