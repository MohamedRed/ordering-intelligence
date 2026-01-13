package com.orderingintelligence.auto

fun formatCents(cents: Int): String {
  return String.format("%.2f", cents / 100.0)
}
