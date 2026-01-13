package com.orderingintelligence.auto

import androidx.car.app.CarAppService
import androidx.car.app.Session

class OrderingCarAppService : CarAppService() {
  override fun onCreateSession(): Session {
    return OrderingCarSession()
  }
}
