package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/metainfo"
)

// A pre-buffer job downloads a file (or just its first Want bytes) in the
// background, ahead of time, and protects it from cache clean-up until the
// user removes it.
type job struct {
	Hash     string   `json:"hash"`
	Idx      int      `json:"idx"`
	Want     int64    `json:"want"` // bytes from the start of the file; 0 = all
	Label    string   `json:"label"`
	Trackers []string `json:"trackers,omitempty"`
	Name     string   `json:"name,omitempty"`

	// Live state (not saved).
	state string // "metadata" | "downloading" | "ready" | "error"
	err   string
	size  int64
}

type jobs struct {
	mu   sync.Mutex
	list map[string]*job
}

func jobKey(hash string, idx int) string { return strings.ToLower(hash) + "/" + strconv.Itoa(idx) }

func (s *server) jobsPath() string { return filepath.Join(s.dataDir, ".meta", "prebuffer.json") }

func (s *server) saveJobs() {
	s.jobs.mu.Lock()
	var out []*job
	for _, j := range s.jobs.list {
		out = append(out, j)
	}
	b, _ := json.Marshal(out)
	s.jobs.mu.Unlock()
	_ = os.MkdirAll(filepath.Dir(s.jobsPath()), 0o755)
	_ = os.WriteFile(s.jobsPath(), b, 0o644)
}

// loadJobs restores saved jobs and resumes them (the data is still on disk).
func (s *server) loadJobs() {
	b, err := os.ReadFile(s.jobsPath())
	if err != nil {
		return
	}
	var saved []*job
	if json.Unmarshal(b, &saved) != nil {
		return
	}
	for _, j := range saved {
		s.startJob(j)
	}
}

// pinned reports whether a torrent has a pre-buffer job (so it must not be
// evicted from the cache).
func (s *server) pinned(h metainfo.Hash) bool {
	s.jobs.mu.Lock()
	defer s.jobs.mu.Unlock()
	hex := h.HexString()
	for _, j := range s.jobs.list {
		if strings.EqualFold(j.Hash, hex) {
			return true
		}
	}
	return false
}

func (s *server) pinnedBytes() int64 {
	s.jobs.mu.Lock()
	defer s.jobs.mu.Unlock()
	var n int64
	for _, j := range s.jobs.list {
		n += j.size
	}
	return n
}

// startJob registers the job and begins it in the background.
func (s *server) startJob(j *job) {
	j.Hash = strings.ToLower(j.Hash)
	j.state = "metadata"
	key := jobKey(j.Hash, j.Idx)
	s.jobs.mu.Lock()
	if old, ok := s.jobs.list[key]; ok && old.state != "error" {
		s.jobs.mu.Unlock()
		return
	}
	s.jobs.list[key] = j
	s.jobs.mu.Unlock()
	s.saveJobs()

	go func() {
		fail := func(msg string) {
			s.jobs.mu.Lock()
			j.state, j.err = "error", msg
			s.jobs.mu.Unlock()
		}
		t, err := s.addTorrent(context.Background(), j.Hash, j.Trackers, j.Name)
		if err != nil {
			fail(err.Error())
			return
		}
		files := t.Files()
		if j.Idx < 0 || j.Idx >= len(files) {
			fail("file not found in torrent")
			return
		}
		f := files[j.Idx]
		s.jobs.mu.Lock()
		j.size = f.Length() // files are created at full length: count it all
		s.jobs.mu.Unlock()
		if msg := s.admit(t, f); msg != "" {
			fail(msg)
			return
		}
		s.touch(t.InfoHash(), 0)
		if j.Want > 0 && j.Want < f.Length() {
			plen := t.Info().PieceLength
			begin := f.BeginPieceIndex()
			end := begin + int((j.Want+plen-1)/plen)
			if end > f.EndPieceIndex() {
				end = f.EndPieceIndex()
			}
			t.DownloadPieces(begin, end)
		} else {
			f.Download()
		}
		s.jobs.mu.Lock()
		j.state = "downloading"
		s.jobs.mu.Unlock()
	}()
}

// jobProgress is computed live from the torrent.
func (s *server) jobProgress(j *job) (done, total int64) {
	var ih metainfo.Hash
	if ih.FromHexString(j.Hash) != nil {
		return 0, 0
	}
	t, ok := s.client.Torrent(ih)
	if !ok || t.Info() == nil || j.Idx >= len(t.Files()) {
		return 0, 0
	}
	f := t.Files()[j.Idx]
	if j.Want <= 0 || j.Want >= f.Length() {
		return f.BytesCompleted(), f.Length()
	}
	plen := t.Info().PieceLength
	begin := f.BeginPieceIndex()
	end := begin + int((j.Want+plen-1)/plen)
	if end > f.EndPieceIndex() {
		end = f.EndPieceIndex()
	}
	for i := begin; i < end; i++ {
		l := t.Info().Piece(i).Length()
		total += l
		if t.PieceState(i).Complete {
			done += l
		}
	}
	return done, total
}

// handlePrebuffer:
//
//	GET /prebuffer                                   -> list jobs with progress
//	GET /prebuffer/<hash>/<idx>?want=&label=&tr=&dn= -> start a job
//	GET /prebuffer/<hash>/<idx>?remove=1             -> cancel and delete it
func (s *server) handlePrebuffer(w http.ResponseWriter, r *http.Request) {
	rest := strings.Trim(strings.TrimPrefix(r.URL.Path, "/prebuffer"), "/")
	q := r.URL.Query()
	if rest == "" {
		s.jobs.mu.Lock()
		var snapshot []*job
		for _, j := range s.jobs.list {
			snapshot = append(snapshot, j)
		}
		s.jobs.mu.Unlock()
		out := []map[string]any{}
		for _, j := range snapshot {
			done, total := s.jobProgress(j)
			s.jobs.mu.Lock()
			if j.state == "downloading" && total > 0 && done >= total {
				j.state = "ready"
			}
			out = append(out, map[string]any{
				"hash": j.Hash, "idx": j.Idx, "label": j.Label, "want": j.Want,
				"state": j.state, "error": j.err, "done": done, "total": total,
				"size": j.size,
			})
			s.jobs.mu.Unlock()
		}
		sort.Slice(out, func(a, b int) bool { return out[a]["label"].(string) < out[b]["label"].(string) })
		writeJSON(w, out)
		return
	}
	parts := strings.Split(rest, "/")
	if len(parts) != 2 {
		http.Error(w, "usage: /prebuffer/<hash>/<fileIdx>", http.StatusBadRequest)
		return
	}
	idx, err := strconv.Atoi(parts[1])
	if err != nil {
		http.Error(w, "usage: /prebuffer/<hash>/<fileIdx>", http.StatusBadRequest)
		return
	}
	hash := strings.ToLower(parts[0])
	if q.Get("remove") == "1" {
		s.removeJob(hash, idx)
		writeJSON(w, map[string]any{"ok": true})
		return
	}
	want, _ := strconv.ParseInt(q.Get("want"), 10, 64)
	s.startJob(&job{Hash: hash, Idx: idx, Want: want, Label: q.Get("label"), Trackers: q["tr"], Name: q.Get("dn")})
	writeJSON(w, map[string]any{"ok": true})
}

func (s *server) removeJob(hash string, idx int) {
	key := jobKey(hash, idx)
	s.jobs.mu.Lock()
	delete(s.jobs.list, key)
	s.jobs.mu.Unlock()
	s.saveJobs()
	var ih metainfo.Hash
	if ih.FromHexString(hash) != nil {
		return
	}
	t, ok := s.client.Torrent(ih)
	if !ok {
		return
	}
	if t.Info() != nil && idx < len(t.Files()) {
		t.Files()[idx].Cancel()
	}
	if s.pinned(ih) {
		return // another file of the same torrent is still pre-buffered
	}
	s.mu.Lock()
	busy := s.used[ih] != nil && s.used[ih].readers > 0
	s.mu.Unlock()
	if busy {
		return // being watched: the normal clean-up removes it later
	}
	name := t.Name()
	t.Drop()
	if name != "" {
		_ = os.RemoveAll(filepath.Join(s.dataDir, name))
	}
}

// admit decides whether a file may be downloaded: it must fit the cache limit
// (after evicting idle, unprotected torrents) and the free space on the disk.
// Returns "" if fine, else a message for the user. Files are created at their
// full length, so the whole length counts, not just what is downloaded.
func (s *server) admit(t *torrent.Torrent, f *torrent.File) string {
	size := f.Length()
	max := s.maxCache
	if size > max {
		return fmt.Sprintf("This file is %s, larger than your %s cache limit. Pick a smaller source or raise the limit in Settings.", gb(size), gb(max))
	}
	need := size - f.BytesCompleted()
	s.evictUntil(max-need, t.InfoHash())
	if cur := dirSize(s.dataDir); cur+need > max {
		return fmt.Sprintf("Not enough room in the %s cache: pre-buffered items are using %s. Remove some, or raise the limit in Settings.", gb(max), gb(s.pinnedBytes()))
	}
	if free := freeDiskBytes(s.dataDir); free >= 0 && free < need+(1<<29) {
		return fmt.Sprintf("Not enough free disk space: need about %s, only %s free. Free up space and try again.", gb(need), gb(free))
	}
	return ""
}

func gb(n int64) string { return fmt.Sprintf("%.1f GB", float64(n)/(1<<30)) }

// evictUntil removes least-recently-used idle torrents (never pre-buffered or
// 'keep' ones) until the cache is at most target bytes.
func (s *server) evictUntil(target int64, keep metainfo.Hash) {
	size := dirSize(s.dataDir)
	if size <= target {
		return
	}
	s.mu.Lock()
	type cand struct {
		h metainfo.Hash
		u *usage
	}
	var cands []cand
	for h, u := range s.used {
		if u.readers == 0 && h != keep {
			cands = append(cands, cand{h, u})
		}
	}
	sort.Slice(cands, func(i, j int) bool { return cands[i].u.last.Before(cands[j].u.last) })
	s.mu.Unlock()

	for _, c := range cands {
		if size <= target {
			break
		}
		if s.pinned(c.h) {
			continue
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

// handleCheck: /check/<hash>/<idx>?tr=&dn= fetches the torrent's metadata and
// says whether the file may be played, so the app can show a clear message
// instead of a failed stream.
func (s *server) handleCheck(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.Trim(strings.TrimPrefix(r.URL.Path, "/check/"), "/"), "/")
	if len(parts) < 1 || parts[0] == "" {
		http.Error(w, "usage: /check/<hash>/<idx>", http.StatusBadRequest)
		return
	}
	idx := "auto"
	if len(parts) > 1 {
		idx = parts[1]
	}
	q := r.URL.Query()
	t, err := s.addTorrent(r.Context(), parts[0], q["tr"], q.Get("dn"))
	if err != nil {
		writeJSON(w, map[string]any{"ok": false, "message": err.Error()})
		return
	}
	f := pickFile(t, idx)
	if f == nil {
		writeJSON(w, map[string]any{"ok": false, "message": "torrent has no files"})
		return
	}
	msg := s.admit(t, f)
	s.touch(t.InfoHash(), 0)
	index := -1 // position of the chosen file (the app needs it to pre-buffer)
	for i, ff := range t.Files() {
		if ff.Offset() == f.Offset() && ff.Length() == f.Length() {
			index = i
			break
		}
	}
	writeJSON(w, map[string]any{"ok": msg == "", "message": msg, "size": f.Length(), "idx": index})
}

func (s *server) handleDisk(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]any{
		"free":       freeDiskBytes(s.dataDir),
		"cacheBytes": dirSize(s.dataDir),
		"maxCache":   s.maxCache,
		"pinned":     s.pinnedBytes(),
	})
}
