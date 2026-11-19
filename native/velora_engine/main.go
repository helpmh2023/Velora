// velora_engine: a tiny torrent-streaming server.
//
// Flutter starts this process, reads the port it prints, then plays
//
//	http://127.0.0.1:<port>/stream/<infoHash>/<fileIdx>
//
// like any ordinary video URL. Pieces are fetched on demand (sequentially
// around the playback position), so playback starts before the download ends.
//
// Endpoints (all GET, loopback only):
//
//	/health                      -> {"ok":true}
//	/stream/<hash>/<idx|auto>    -> the video file, Range requests supported
//	                                optional query: tr=<tracker> (repeatable), dn=<name>
//	/status/<hash>               -> peers, progress, file list
//
// Lifetime: exits when stdin closes (i.e. when the parent app dies).
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/metainfo"
	"golang.org/x/time/rate"
)

const (
	metadataTimeout = 75 * time.Second
	readahead       = 24 << 20 // 24 MiB
)

var videoExt = map[string]bool{
	".mkv": true, ".mp4": true, ".avi": true, ".mov": true, ".m4v": true,
	".webm": true, ".ts": true, ".m2ts": true, ".wmv": true, ".flv": true,
}

type usage struct {
	last    time.Time
	readers int
}

type server struct {
	bound    net.IP
	client   *torrent.Client
	dataDir  string
	maxCache int64

	mu   sync.Mutex
	used map[metainfo.Hash]*usage
}

func main() {
	var (
		dataDir    = flag.String("data-dir", filepath.Join(os.TempDir(), "velora-cache"), "cache directory")
		maxCacheG  = flag.Float64("max-cache-gb", 4, "cache size cap in GiB")
		uploadK    = flag.Int("upload-kbps", 1, "upload limit in KiB/s (minimum 1)")
		bindIP     = flag.String("bind-ip", "", "bind all peer/tracker traffic to this local address (e.g. a VPN adapter); refuse to run if it is missing")
		noUpload   = flag.Bool("no-upload", false, "do not upload at all")
		freshCache = flag.Bool("fresh-cache", false, "delete the cache folder at start (default: keep it between runs)")
		host       = flag.String("host", "127.0.0.1", "bind address (keep loopback unless you know why)")
		port       = flag.Int("port", 0, "HTTP port (0 = pick a free one)")
	)
	flag.Parse()
	log.SetFlags(log.Ltime)

	// By default the cache survives restarts, so a title you already
	// downloaded (or part of it) is not downloaded again. --fresh-cache wipes
	// it first; either way the folder is trimmed to the size cap.
	if *freshCache {
		_ = os.RemoveAll(*dataDir)
	}
	if err := os.MkdirAll(*dataDir, 0o755); err != nil {
		log.Fatalf("cache dir: %v", err)
	}
	trimCache(*dataDir, int64(*maxCacheG*(1<<30)))

	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = *dataDir
	cfg.ListenPort = 0
	cfg.Seed = false
	cfg.NoUpload = *noUpload
	up := *uploadK
	if up < 1 {
		up = 1
	}
	// Burst only needs to cover one 16 KiB block; keep it tiny so the limit
	// really is the limit.
	cfg.UploadRateLimiter = rate.NewLimiter(rate.Limit(up*1024), 64<<10)

	// Network binding: every socket (peers, DHT, UDP trackers) listens on, and
	// dials from, this one address. If it does not exist (VPN down) we stop
	// instead of silently falling back to the real connection.
	var bound net.IP
	if *bindIP != "" {
		bound = net.ParseIP(*bindIP)
		if bound == nil {
			fatal("bind address %q is not a valid IP", *bindIP)
		}
		if !hasLocalAddr(bound) {
			fatal("network adapter with address %s not found (is the VPN connected?)", bound)
		}
		host := bound.String()
		cfg.ListenHost = func(string) string { return host }
		if bound.To4() != nil {
			cfg.DisableIPv6 = true // a v6 socket could bypass the v4 VPN address
		} else {
			cfg.DisableIPv4 = true
			cfg.DisableIPv4Peers = true
		}
		cfg.NoDefaultPortForwarding = true // do not ask the router to open ports
		dialer := &net.Dialer{LocalAddr: &net.TCPAddr{IP: bound}, Timeout: 20 * time.Second}
		cfg.HTTPDialContext = dialer.DialContext // HTTP(S) trackers
	}

	client, err := torrent.NewClient(cfg)
	if err != nil {
		log.Fatalf("torrent client: %v", err)
	}
	defer client.Close()

	s := &server{
		bound:    bound,
		client:   client,
		dataDir:  *dataDir,
		maxCache: int64(*maxCacheG * (1 << 30)),
		used:     map[metainfo.Hash]*usage{},
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]any{"ok": true})
	})
	mux.HandleFunc("/myip", s.handleMyIP)
	mux.HandleFunc("/stream/", s.handleStream)
	mux.HandleFunc("/status/", s.handleStatus)

	ln, err := net.Listen("tcp", net.JoinHostPort(*host, strconv.Itoa(*port)))
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	// The parent parses this exact line.
	fmt.Printf("VELORA_ENGINE_READY port=%d\n", ln.Addr().(*net.TCPAddr).Port)
	_ = os.Stdout.Sync()

	go s.sweepCache()
	go func() { // parent died -> stdin closes -> exit
		_, _ = io.Copy(io.Discard, os.Stdin)
		client.Close()
		os.Exit(0)
	}()

	srv := &http.Server{Handler: mux}
	log.Fatal(srv.Serve(ln))
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

// addTorrent registers (or finds) the torrent and waits for its metadata.
func (s *server) addTorrent(ctx context.Context, hash string, trackers []string, name string) (*torrent.Torrent, error) {
	var ih metainfo.Hash
	if err := ih.FromHexString(strings.ToLower(hash)); err != nil {
		return nil, fmt.Errorf("bad info hash %q", hash)
	}
	spec := &torrent.TorrentSpec{InfoHash: ih, DisplayName: name}
	// If we have seen this torrent before, its file list was saved: load it, so
	// pieces already on disk can be served immediately, even with no peers.
	if mi, err := metainfo.LoadFromFile(s.metaPath(ih)); err == nil {
		spec = torrent.TorrentSpecFromMetaInfo(mi)
		if name != "" {
			spec.DisplayName = name
		}
	}
	if len(trackers) > 0 {
		spec.Trackers = append(spec.Trackers, trackers)
	}
	t, _, err := s.client.AddTorrentSpec(spec)
	if err != nil {
		return nil, err
	}
	select {
	case <-t.GotInfo():
		s.saveMeta(t)
		return t, nil
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(metadataTimeout):
		return nil, fmt.Errorf("timed out finding peers (no metadata after %s)", metadataTimeout)
	}
}

// pickFile honours the requested index, else falls back to the largest video.
func pickFile(t *torrent.Torrent, idxStr string) *torrent.File {
	files := t.Files()
	if i, err := strconv.Atoi(idxStr); err == nil && i >= 0 && i < len(files) {
		return files[i]
	}
	var best *torrent.File
	for _, f := range files {
		if !videoExt[strings.ToLower(filepath.Ext(f.DisplayPath()))] {
			continue
		}
		if best == nil || f.Length() > best.Length() {
			best = f
		}
	}
	if best == nil {
		for _, f := range files {
			if best == nil || f.Length() > best.Length() {
				best = f
			}
		}
	}
	return best
}

func (s *server) touch(h metainfo.Hash, delta int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	u := s.used[h]
	if u == nil {
		u = &usage{}
		s.used[h] = u
	}
	u.last = time.Now()
	u.readers += delta
}

func (s *server) handleStream(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/stream/"), "/"), "/")
	if len(parts) < 1 || parts[0] == "" {
		http.Error(w, "usage: /stream/<infoHash>/<fileIdx|auto>", http.StatusBadRequest)
		return
	}
	idx := "auto"
	if len(parts) > 1 {
		idx = parts[1]
	}
	q := r.URL.Query()

	t, err := s.addTorrent(r.Context(), parts[0], q["tr"], q.Get("dn"))
	if err != nil {
		http.Error(w, err.Error(), http.StatusGatewayTimeout)
		return
	}
	f := pickFile(t, idx)
	if f == nil {
		http.Error(w, "torrent has no files", http.StatusNotFound)
		return
	}

	s.touch(t.InfoHash(), +1)
	defer s.touch(t.InfoHash(), -1)

	rd := f.NewReader()
	defer rd.Close()
	rd.SetContext(r.Context())
	rd.SetResponsive()
	rd.SetReadahead(readahead)

	w.Header().Set("Accept-Ranges", "bytes")
	http.ServeContent(w, r, filepath.Base(f.DisplayPath()), time.Time{}, rd)
}

func (s *server) handleStatus(w http.ResponseWriter, r *http.Request) {
	hash := strings.Trim(strings.TrimPrefix(r.URL.Path, "/status/"), "/")
	var ih metainfo.Hash
	if err := ih.FromHexString(strings.ToLower(hash)); err != nil {
		http.Error(w, "bad info hash", http.StatusBadRequest)
		return
	}
	t, ok := s.client.Torrent(ih)
	if !ok {
		http.Error(w, "unknown torrent", http.StatusNotFound)
		return
	}
	st := t.Stats()
	out := map[string]any{
		"name":        t.Name(),
		"peers":       st.ActivePeers,
		"totalPeers":  st.TotalPeers,
		"seeders":     st.ConnectedSeeders,
		"hasMetadata": t.Info() != nil,
	}
	if t.Info() != nil {
		out["length"] = t.Length()
		out["completed"] = t.BytesCompleted()
		type fi struct {
			Index  int    `json:"index"`
			Path   string `json:"path"`
			Length int64  `json:"length"`
		}
		var files []fi
		for i, f := range t.Files() {
			files = append(files, fi{i, f.DisplayPath(), f.Length()})
		}
		out["files"] = files
	}
	writeJSON(w, out)
}

// sweepCache keeps the cache under its cap by dropping the least recently
// used torrents that nobody is currently reading.
func (s *server) sweepCache() {
	for range time.Tick(30 * time.Second) {
		size := dirSize(s.dataDir)
		if size <= s.maxCache {
			continue
		}
		s.mu.Lock()
		type cand struct {
			h metainfo.Hash
			u *usage
		}
		var cands []cand
		for h, u := range s.used {
			if u.readers == 0 {
				cands = append(cands, cand{h, u})
			}
		}
		sort.Slice(cands, func(i, j int) bool { return cands[i].u.last.Before(cands[j].u.last) })
		s.mu.Unlock()

		for _, c := range cands {
			if size <= s.maxCache {
				break
			}
			if t, ok := s.client.Torrent(c.h); ok {
				name := t.Name()
				t.Drop()
				if name != "" {
					_ = os.RemoveAll(filepath.Join(s.dataDir, name))
				}
			}
			s.mu.Lock()
			delete(s.used, c.h)
			s.mu.Unlock()
			size = dirSize(s.dataDir)
		}
	}
}

func dirSize(dir string) int64 {
	var n int64
	_ = filepath.Walk(dir, func(_ string, info os.FileInfo, err error) error {
		if err == nil && !info.IsDir() {
			n += info.Size()
		}
		return nil
	})
	return n
}

// fatal reports a startup problem on stdout (the parent shows it to the user)
// and exits. Stdout rather than stderr so it is easy to capture.
func fatal(format string, a ...any) {
	fmt.Printf("VELORA_ENGINE_ERROR %s\n", fmt.Sprintf(format, a...))
	_ = os.Stdout.Sync()
	os.Exit(3)
}

func hasLocalAddr(ip net.IP) bool {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return false
	}
	for _, a := range addrs {
		if n, ok := a.(*net.IPNet); ok && n.IP.Equal(ip) {
			return true
		}
	}
	return false
}

// handleMyIP reports the public address the outside world sees for traffic
// leaving through the engine's network binding (so the app can show whether
// the VPN is actually masking you). One request to a public "what is my IP"
// service, made from the same bound address the torrent traffic uses.
func (s *server) handleMyIP(w http.ResponseWriter, r *http.Request) {
	dialer := &net.Dialer{Timeout: 10 * time.Second}
	if s.bound != nil {
		dialer.LocalAddr = &net.TCPAddr{IP: s.bound}
	}
	client := &http.Client{
		Timeout:   15 * time.Second,
		Transport: &http.Transport{DialContext: dialer.DialContext, Proxy: nil},
	}
	resp, err := client.Get("https://api.ipify.org")
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 128))
	out := map[string]any{"ip": strings.TrimSpace(string(body)), "bound": s.bound != nil}
	if s.bound != nil {
		out["bindAddress"] = s.bound.String()
	}
	writeJSON(w, out)
}

// trimCache brings a cache folder from an earlier run back under [max] bytes by
// deleting the least recently used torrent folders/files first. If anything is
// deleted the piece-completion database (".torrent*") is removed too, so it can
// never claim pieces are complete whose files are gone; it is rebuilt by
// verifying whatever data remains.
func trimCache(dir string, max int64) {
	type entry struct {
		path  string
		size  int64
		mtime time.Time
	}
	items, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	var entries []entry
	var total int64
	for _, it := range items {
		if strings.HasPrefix(it.Name(), ".") {
			continue // the completion database; handled below
		}
		p := filepath.Join(dir, it.Name())
		e := entry{path: p}
		_ = filepath.Walk(p, func(_ string, info os.FileInfo, err error) error {
			if err != nil || info == nil {
				return nil
			}
			if !info.IsDir() {
				e.size += info.Size()
			}
			if info.ModTime().After(e.mtime) {
				e.mtime = info.ModTime()
			}
			return nil
		})
		total += e.size
		entries = append(entries, e)
	}
	if total <= max {
		return
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].mtime.Before(entries[j].mtime) })
	removed := false
	for _, e := range entries {
		if total <= max {
			break
		}
		if os.RemoveAll(e.path) == nil {
			total -= e.size
			removed = true
		}
	}
	if removed {
		for _, it := range items {
			if strings.HasPrefix(it.Name(), ".torrent") {
				_ = os.RemoveAll(filepath.Join(dir, it.Name()))
			}
		}
	}
}

// metaPath is where a torrent's file list (its .torrent metadata) is kept. The
// folder starts with a dot, so the cache trimmer never deletes it; the files
// are a few KB each.
func (s *server) metaPath(ih metainfo.Hash) string {
	return filepath.Join(s.dataDir, ".meta", ih.HexString()+".torrent")
}

// saveMeta remembers a torrent's metadata the first time we learn it.
func (s *server) saveMeta(t *torrent.Torrent) {
	path := s.metaPath(t.InfoHash())
	if _, err := os.Stat(path); err == nil {
		return
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	f, err := os.Create(path)
	if err != nil {
		return
	}
	defer f.Close()
	mi := t.Metainfo()
	_ = mi.Write(f)
}
