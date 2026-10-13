package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sync"
	"time"
)

var (
	mu       sync.Mutex
	counters = map[string]uint64{}
)

func incr(name string, v uint64) {
	mu.Lock()
	counters[name] += v
	mu.Unlock()
}

func cpuBurn(d time.Duration) {
	end := time.Now().Add(d)
	for time.Now().Before(end) {
		for i := 0; i < 10_000; i++ {
		}
	}
}

var quotes = []string{
	"Simplicity is a feature.",
	"Shipping beats perfection.",
	"The bottleneck is upstream of the terminal.",
	"Idempotency is a lifestyle.",
	"Observability is not optional.",
}

func quoteHandler(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	cpuBurn(100 * time.Millisecond)
	q := quotes[time.Now().UnixNano()%int64(len(quotes))]
	incr("quote_api_requests_total", 1)
	incr("quote_api_cpu_ms_total", 100)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = r
	json.NewEncoder(w).Encode(map[string]any{
		"quote":        q,
		"elapsed_ms":   time.Since(start).Milliseconds(),
	})
}

func healthz(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

func readyz(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ready"))
}

func metrics(w http.ResponseWriter, r *http.Request) {
	mu.Lock()
	counted := make(map[string]uint64, len(counters))
	for k, v := range counters {
		counted[k] = v
	}
	mu.Unlock()
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	fmt.Fprint(w, "# HELP quote_api_requests_total Total handled requests.\n# TYPE quote_api_requests_total counter\n")
	fmt.Fprintf(w, "quote_api_requests_total %d\n", counted["quote_api_requests_total"])
	fmt.Fprint(w, "# HELP quote_api_cpu_ms_total Total simulated CPU cost in ms.\n# TYPE quote_api_cpu_ms_total counter\n")
	fmt.Fprintf(w, "quote_api_cpu_ms_total %d\n", counted["quote_api_cpu_ms_total"])
}

func main() {
	id := make([]byte, 6)
	if _, err := rand.Read(id); err != nil {
		fmt.Fprintln(os.Stderr, "rand:", err)
		os.Exit(1)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthz)
	mux.HandleFunc("/readyz", readyz)
	mux.HandleFunc("/metrics", metrics)
	mux.HandleFunc("/api/quote", quoteHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	fmt.Fprintf(os.Stderr, "quote-api listening on %s (instance %s)\n", port, hex.EncodeToString(id))
	if err := srv.ListenAndServe(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
