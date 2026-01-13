package com.orderingintelligence.auto

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session

class OrderingCarSession : Session() {
  override fun onCreateScreen(intent: Intent): Screen {
    return ReorderScreen(carContext)
  }
}
