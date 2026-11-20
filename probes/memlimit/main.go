// memhog is a deliberately misbehaving actor for probing Substrate's
// per-actor memory enforcement: GET /alloc?mib=N allocates and touches N MiB
// and holds it, so an actor can be pushed past its memoryBytes limit on
// demand while a neighbour on the same worker keeps answering GET /.
package main

import (
	"fmt"
	"log"
	"net/http"
	"strconv"
	"sync"
)

var (
	mu   sync.Mutex
	held [][]byte
)

func heldMiB() int {
	mu.Lock()
	defer mu.Unlock()
	return len(held)
}

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprintf(w, "alive, holding %d MiB\n", heldMiB())
	})
	http.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	http.HandleFunc("/alloc", func(w http.ResponseWriter, r *http.Request) {
		n, err := strconv.Atoi(r.URL.Query().Get("mib"))
		if err != nil || n <= 0 {
			http.Error(w, "mib must be a positive integer", http.StatusBadRequest)
			return
		}
		for i := 0; i < n; i++ {
			b := make([]byte, 1<<20)
			for j := 0; j < len(b); j += 4096 {
				b[j] = 1 // touch every page so it is resident, not just reserved
			}
			mu.Lock()
			held = append(held, b)
			mu.Unlock()
		}
		fmt.Fprintf(w, "allocated %d MiB, holding %d MiB\n", n, heldMiB())
	})
	log.Fatal(http.ListenAndServe(":80", nil))
}
