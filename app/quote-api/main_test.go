package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHealthEndpointsOK(t *testing.T) {
	for _, path := range []string{"/healthz", "/readyz"} {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		w := httptest.NewRecorder()
		switch path {
		case "/healthz":
			healthz(w, req)
		default:
			readyz(w, req)
		}
		if w.Code != http.StatusOK {
			t.Errorf("%s: got %d, want 200", path, w.Code)
		}
	}
}

func TestQuoteHandlerSimulatesCPU(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/quote", nil)
	w := httptest.NewRecorder()
	quoteHandler(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("quote: got %d, want 200", w.Code)
	}

	var body map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatalf("quote body not json: %v", err)
	}
	quote, _ := body["quote"].(string)
	if quote == "" {
		t.Error("quote missing")
	}
	elapsed, _ := body["elapsed_ms"].(float64)
	if elapsed < 90 { // ~100ms of simulated CPU work required
		t.Errorf("elapsed_ms=%v, want >=90 (CPU simulation missing)", elapsed)
	}
}

func TestMetricsExposeCounter(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	w := httptest.NewRecorder()
	metrics(w, req)
	out := w.Body.String()
	if !strings.Contains(out, "# HELP quote_api_requests_total") {
		t.Error("metrics missing quote_api_requests_total help header")
	}
	if !strings.Contains(out, "quote_api_requests_total 1") {
		t.Error("metrics counter not incremented after quote call")
	}
}

func TestQuoteLatencyUnderDur(t *testing.T) {
	done := make(chan struct{})
	go func() {
		w := httptest.NewRecorder()
		quoteHandler(w, httptest.NewRequest(http.MethodGet, "/api/quote", nil))
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("quote handler did not finish within 2s (CPU sim broken)")
	}
}
