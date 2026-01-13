package com.orderingintelligence.auto

sealed class ReorderScreenState {
  object Loading : ReorderScreenState()

  data class Loaded(
    val orders: List<AutoReorder>,
    val fuelGrades: List<AutoMenuItem>,
    val session: AutoSessionInfo?,
    val hasDefaultPaymentMethod: Boolean
  ) : ReorderScreenState()

  data class Error(val message: String) : ReorderScreenState()
}
