package main

import "testing"

func TestServiceURLEscapesPathSegments(t *testing.T) {
	got := serviceURL("https://payments.example/", "orders", "order 1/2", "checkout")
	want := "https://payments.example/orders/order%201%2F2/checkout"
	if got != want {
		t.Fatalf("expected %q, got %q", want, got)
	}
}
