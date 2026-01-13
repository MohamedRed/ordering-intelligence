package main

import "testing"

func TestExtractRadarMatrixDurations(t *testing.T) {
	body := []byte(`{
    "matrix": [
      [
        {"distance": {"value": 1200}, "duration": {"value": 300}},
        {"distance": {"value": 1500}, "duration": {"value": 420}}
      ],
      [
        {"distance": {"value": 800}, "duration": {"value": 200}},
        {"distance": {"value": 900}, "duration": {"value": 240}}
      ]
    ]
  }`)
	matrix, err := extractRadarMatrixDurations(body)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(matrix) != 2 || len(matrix[0]) != 2 {
		t.Fatalf("unexpected matrix size: %#v", matrix)
	}
	if matrix[0][0] != 300 || matrix[1][1] != 240 {
		t.Fatalf("unexpected durations: %#v", matrix)
	}
}

func TestExtractRadarOptimizeOrder(t *testing.T) {
	body := []byte(`{
    "route": {
      "legs": [
        {"startIndex": 0, "endIndex": 2},
        {"startIndex": 2, "endIndex": 1},
        {"startIndex": 1, "endIndex": 3}
      ]
    }
  }`)
	order, err := extractRadarOptimizeOrder(body)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	expected := []int{0, 2, 1, 3}
	if len(order) != len(expected) {
		t.Fatalf("unexpected order length: %v", order)
	}
	for i := range expected {
		if order[i] != expected[i] {
			t.Fatalf("unexpected order at %d: %v", i, order)
		}
	}
}
