#!/usr/bin/env python3
"""Unit tests for tui.py pure helpers — no GPU, no live Textual app.

Run with the project venv interpreter (Textual is only installed there):
    .venv/bin/python3 scripts/test_tui.py

Covers the logic-bearing seams: progress-line parsing, sidecar normalization,
ETA aggregation, scan/selection defaults, and the key-binding surface. The
interactive App is exercised separately by the manual TUI test plan in test.sh.
"""
from __future__ import annotations

import os
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import tui  # noqa: E402


class ParseVideoProgress(unittest.TestCase):
    def test_extracts_pct_fps_and_eta(self) -> None:
        line = "frame=450/9000 (5%); fps=3.5; elapsed=00:02:09; remaining=01:09:00"
        got = tui.parse_video_progress(line)
        self.assertEqual(got, {"pct": 5, "throughput": "3.5 fps", "eta": "01:09:00"})

    def test_strips_ansi_and_carriage_return(self) -> None:
        line = "\x1b[2K\rframe=10/100; fps=1; elapsed=00:00:10; remaining=00:01:30"
        got = tui.parse_video_progress(line)
        assert got is not None
        self.assertEqual(got["pct"], 10)

    def test_non_progress_line_returns_none(self) -> None:
        self.assertIsNone(tui.parse_video_progress("[info] loading model"))


class ParseImageProgress(unittest.TestCase):
    def test_testing_line_maps_to_pct(self) -> None:
        # "Testing 0 name" is the first of 4 files -> ~25%.
        got = tui.parse_image_progress("Testing 0 butterfly", total_files=4)
        self.assertEqual(got, {"pct": 25, "throughput": ""})

    def test_tile_line_reports_throughput_not_pct(self) -> None:
        got = tui.parse_image_progress("\tTile 3/16", total_files=4)
        self.assertEqual(got, {"pct": None, "throughput": "tile 3/16"})

    def test_pct_capped_at_99(self) -> None:
        got = tui.parse_image_progress("Testing 9 last", total_files=4)
        assert got is not None
        self.assertEqual(got["pct"], 99)


class NormalizeSidecar(unittest.TestCase):
    """Reattach poller must read the script-emitted sidecar fields correctly.

    Regression: video writes `fps`, but the poller previously read `throughput`
    and silently dropped the rate on a reattached job.
    """

    def test_video_fps_becomes_throughput(self) -> None:
        data = {"status": "running", "pct": 42, "fps": "3.5", "remaining": "01:00:00"}
        got = tui.normalize_sidecar(data)
        self.assertEqual(got["pct"], 42)
        self.assertEqual(got["throughput"], "3.5 fps")
        self.assertEqual(got["eta"], "01:00:00")

    def test_explicit_throughput_wins_over_fps(self) -> None:
        got = tui.normalize_sidecar({"throughput": "120 files/s", "fps": "9"})
        self.assertEqual(got["throughput"], "120 files/s")

    def test_zero_or_blank_fps_is_omitted(self) -> None:
        for blank in ("0", "", None):
            got = tui.normalize_sidecar({"status": "running", "fps": blank})
            self.assertNotIn("throughput", got)

    def test_image_payload_has_no_throughput_or_eta(self) -> None:
        got = tui.normalize_sidecar({"status": "running", "pct": 50, "elapsed_s": 12})
        self.assertEqual(got["pct"], 50)
        self.assertNotIn("throughput", got)
        self.assertNotIn("eta", got)

    def test_status_defaults_to_running(self) -> None:
        self.assertEqual(tui.normalize_sidecar({})["status"], "running")


class EtaAggregation(unittest.TestCase):
    def _item(self, mtype: str, status: str, selected: bool, est: float) -> tui.MediaItem:
        return tui.MediaItem(
            path=Path(f"/in/{mtype}.x"),
            media_type=mtype,
            output_path=Path(f"/out/{mtype}.x"),
            selected=selected,
            status=status,
            est_seconds=est,
        )

    def test_only_selected_queued_items_contribute(self) -> None:
        items = [
            self._item("image", "queued", True, 120),
            self._item("image", "queued", False, 120),   # unselected
            self._item("image", "done", True, 120),       # done
            self._item("video", "queued", True, 600),
        ]
        text = tui.build_eta_text(items, run_start=None)
        # 120 + 600 = 720 s -> ~12 m total.
        self.assertIn("~12 m", text)
        self.assertIn("1 img", text)
        self.assertIn("1 vid", text)

    def test_no_selection_prompts_user(self) -> None:
        items = [self._item("image", "queued", False, 120)]
        self.assertIn("No items selected", tui.build_eta_text(items, run_start=None))


class ScanSelectionDefaults(unittest.TestCase):
    def test_video_default_selects_only_first_unprocessed(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            src = root / "input" / "video"
            src.mkdir(parents=True)
            for name in ("a.mp4", "b.mp4", "c.mp4"):
                (src / name).write_bytes(b"\x00")
            items = tui.scan_video("medium", root / "input", root / "output")
            self.assertEqual([i.path.name for i in items], ["a.mp4", "b.mp4", "c.mp4"])
            self.assertEqual([i.selected for i in items], [True, False, False])


class KeyBindingSurface(unittest.TestCase):
    """Bindings, footer, and help overlay are all generated from _KEYMAP, so they
    cannot drift. Regression: `d` change-dir was advertised in the footer but had
    no binding, leaving the feature unreachable.
    """

    def _bound_keys(self) -> set[str]:
        return {b.key for b in tui.MediaRestoreApp.BINDINGS}

    def test_change_dir_and_help_are_bound(self) -> None:
        self.assertIn("d", self._bound_keys())
        self.assertIn("question_mark", self._bound_keys())

    def test_bindings_are_generated_from_keymap(self) -> None:
        keymap_keys = {k for e in tui._KEYMAP for (k, _) in e.binds}
        self.assertEqual(keymap_keys, self._bound_keys())

    def test_every_binding_has_an_action_method(self) -> None:
        for b in tui.MediaRestoreApp.BINDINGS:
            method = f"action_{b.action}"
            self.assertTrue(
                hasattr(tui.MediaRestoreApp, method),
                f"binding {b.key!r} -> missing {method}",
            )

    def test_footer_shows_every_action(self) -> None:
        footer = "\n".join(tui.footer_rows())
        for entry in tui._KEYMAP:
            self.assertIn(f"{entry.display}={entry.label}", footer)

    def test_help_overlay_covers_every_action(self) -> None:
        self.assertEqual(len(tui.help_rows()), len(tui._KEYMAP))


class WorkerThreadSafety(unittest.IsolatedAsyncioTestCase):
    """_start_job is an async (thread=False) worker, so it runs on the app's own
    thread. Regression: it called self.call_from_thread(...) there, which raises
    'call_from_thread must run in a different thread from the app'. The progress
    handler must update the UI directly.
    """

    async def test_progress_handler_updates_without_call_from_thread(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as d:
            app = tui.MediaRestoreApp(input_dir=Path(d), preset="medium")
            async with app.run_test():
                item = tui.MediaItem(
                    path=Path("/in/clip.mp4"),
                    media_type="video",
                    output_path=Path("/out/clip.mp4"),
                    status="active",
                )
                app._active_item = item
                # Runs on the app thread; pre-fix this raised RuntimeError.
                app._handle_progress_line(
                    "frame=5/10; fps=2.0; elapsed=00:00:02; remaining=00:00:05",
                    item,
                    1,
                )
                self.assertEqual(item.pct, 50)
                self.assertEqual(item.throughput_str, "2.0 fps")


class SplitProgressStream(unittest.TestCase):
    """video2x redraws its progress bar with '\\r' and no newline. Reading the
    stream by newline alone left the bar at 0% (looked frozen). Splitting on CR
    too lets progress through; CR segments are parsed but not logged.
    """

    def test_cr_segments_parsed_but_not_logged(self) -> None:
        buf = (
            "frame=1/10 (10%); fps=2; elapsed=00:00:01; remaining=00:00:09\r"
            "frame=2/10 (20%); fps=2; elapsed=00:00:02; remaining=00:00:08\r"
        )
        segs, rem = tui.split_progress_stream(buf)
        self.assertEqual(len(segs), 2)
        self.assertTrue(all(is_log is False for _, is_log in segs))
        self.assertEqual(rem, "")

    def test_newline_segment_is_a_log_line(self) -> None:
        segs, rem = tui.split_progress_stream("[FFmpeg] using SAR=1/1\n")
        self.assertEqual(segs, [("[FFmpeg] using SAR=1/1", True)])
        self.assertEqual(rem, "")

    def test_incomplete_tail_is_retained(self) -> None:
        segs, rem = tui.split_progress_stream("done\nframe=3/10 (30%)")
        self.assertEqual(segs, [("done", True)])
        self.assertEqual(rem, "frame=3/10 (30%)")


class EtaWhileActive(unittest.TestCase):
    """The aggregate bar must not announce 'Queue complete' while the final item
    is still being processed."""

    def _item(self, status: str) -> tui.MediaItem:
        return tui.MediaItem(
            path=Path("/in/clip.mp4"), media_type="video",
            output_path=Path("/out/clip.mp4"), status=status, est_seconds=600,
        )

    def test_active_last_item_not_reported_complete(self) -> None:
        text = tui.build_eta_text([self._item("active")], run_start=time.time() - 5)
        self.assertNotIn("Queue complete", text)
        self.assertIn("last item", text)

    def test_genuinely_complete(self) -> None:
        text = tui.build_eta_text([self._item("done")], run_start=time.time() - 5)
        self.assertIn("Queue complete", text)


class PresetControl(unittest.TestCase):
    def test_cycle_action_exists(self) -> None:
        # A modal picker was attempted but reverted (readme TODO); P cycles.
        self.assertTrue(hasattr(tui.MediaRestoreApp, "action_cycle_preset"))
        self.assertFalse(hasattr(tui.MediaRestoreApp, "action_pick_preset"))

    def test_presets_renamed_ultrahigh_to_xhigh(self) -> None:
        self.assertIn("xhigh", tui._PRESETS)
        self.assertNotIn("ultrahigh", tui._PRESETS)
        for media in ("image", "video"):
            self.assertIn("xhigh", tui._ETA_SEEDS[media])
            self.assertNotIn("ultrahigh", tui._ETA_SEEDS[media])


class SectionSurface(unittest.IsolatedAsyncioTestCase):
    """All three media types must appear as section headers, each with its icon.
    Audio is shown but inactive (greyed, no select/start controls)."""

    def test_icon_map_covers_all_three_types(self) -> None:
        for mtype in ("image", "video", "audio"):
            self.assertIn(mtype, tui._SEC_ICONS)
            self.assertTrue(tui._SEC_ICONS[mtype])

    async def test_audio_section_present_and_inactive(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as d:
            app = tui.MediaRestoreApp(input_dir=Path(d))
            async with app.run_test():
                headers = {h._mtype: h for h in app.query(tui.SectionHeader)}
                self.assertEqual(set(headers), {"image", "video", "audio"})
                self.assertTrue(headers["audio"]._inactive)
                self.assertFalse(headers["image"]._inactive)
                self.assertTrue(headers["audio"].has_class("inactive"))
                # Inactive section exposes no select/unselect controls.
                self.assertEqual(len(app.query("#sel-audio")), 0)
                self.assertEqual(len(app.query("#unsel-audio")), 0)


class JobLiveness(unittest.TestCase):
    """A 'running' sidecar left by a dead/finished job must be recognized as
    stale so the item is not stuck '▶ active' forever. PID liveness is
    authoritative; mtime freshness is the fallback for legacy (pid-less) files.
    """

    def _dead_pid(self) -> int:
        import subprocess
        p = subprocess.Popen(["true"])
        p.wait()  # reaped — pid is now free
        return p.pid

    def test_pid_alive_true_for_self(self) -> None:
        self.assertTrue(tui._pid_alive(os.getpid()))

    def test_pid_alive_false_for_dead(self) -> None:
        self.assertFalse(tui._pid_alive(self._dead_pid()))

    def test_dead_pid_overrides_fresh_mtime(self) -> None:
        data = {"status": "running", "pid": self._dead_pid()}
        self.assertFalse(tui.sidecar_job_alive(data, time.time(), time.time()))

    def test_live_pid_overrides_old_mtime(self) -> None:
        data = {"status": "running", "pid": os.getpid()}
        self.assertTrue(tui.sidecar_job_alive(data, time.time() - 9999, time.time()))

    def test_legacy_old_sidecar_is_stale(self) -> None:
        data = {"status": "running"}  # no pid
        self.assertFalse(tui.sidecar_job_alive(data, time.time() - 9999, time.time()))

    def test_legacy_fresh_sidecar_is_alive(self) -> None:
        data = {"status": "running"}  # no pid
        self.assertTrue(tui.sidecar_job_alive(data, time.time() - 2, time.time()))


class FindCompletedOutput(unittest.TestCase):
    """Real-ESRGAN writes '{stem}_out.{ext}', not '{stem}.{ext}'. Output
    detection must match the real file or finished jobs look unprocessed."""

    def test_matches_out_suffix(self) -> None:
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "foo.png"
            (Path(d) / "foo_out.png").write_bytes(b"\x00")
            item = tui.MediaItem(path=Path("/in/foo.png"), media_type="image",
                                 output_path=out)
            self.assertEqual(tui.find_completed_output(item).name, "foo_out.png")

    def test_matches_exact_name_for_video(self) -> None:
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            out = Path(d) / "clip.mp4"
            out.write_bytes(b"\x00")
            item = tui.MediaItem(path=Path("/in/clip.mp4"), media_type="video",
                                 output_path=out)
            self.assertEqual(tui.find_completed_output(item), out)

    def test_none_when_absent(self) -> None:
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            item = tui.MediaItem(path=Path("/in/foo.png"), media_type="image",
                                 output_path=Path(d) / "foo.png")
            self.assertIsNone(tui.find_completed_output(item))


class ZombieActiveReconcile(unittest.IsolatedAsyncioTestCase):
    """Repro for the 'sample-gradient.png stuck ▶ active' bug: a stale 'running'
    sidecar from a dead job must reconcile on startup, not stick active."""

    def _seed(self, root: Path, *, make_output: bool, age: float, pid=None) -> None:
        import json as _json
        (root / "input" / "images").mkdir(parents=True)
        (root / "input" / "images" / "foo.png").write_bytes(b"\x00")
        outdir = root / "output" / "images"
        outdir.mkdir(parents=True)
        if make_output:
            (outdir / "foo_out.png").write_bytes(b"\x00")  # _out suffix
        side = outdir / "foo.png.progress.json"
        payload = {"status": "running", "pct": 100}
        if pid is not None:
            payload["pid"] = pid
        side.write_text(_json.dumps(payload))
        os.utime(side, (time.time() - age, time.time() - age))

    async def _item(self, root: Path) -> tui.MediaItem:
        app = tui.MediaRestoreApp(input_dir=root / "input", output_dir=root / "output")
        async with app.run_test():
            return next(i for i in app._items if i.path.name == "foo.png")

    async def test_finished_job_reconciles_to_done(self) -> None:
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            self._seed(root, make_output=True, age=3600)
            item = await self._item(root)
            self.assertEqual(item.status, "done")

    async def test_crashed_job_without_output_resets_to_queued(self) -> None:
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            self._seed(root, make_output=False, age=3600)
            item = await self._item(root)
            self.assertNotEqual(item.status, "active")

    async def test_genuinely_live_detached_job_stays_active(self) -> None:
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            # fresh sidecar, our own (live) pid -> a real running detached job
            self._seed(root, make_output=False, age=1, pid=os.getpid())
            item = await self._item(root)
            self.assertEqual(item.status, "active")


class ActivePanelLiveness(unittest.IsolatedAsyncioTestCase):
    """The elapsed clock must tick even before any progress line arrives, so the
    panel is never ambiguous about whether the job is alive."""

    async def test_elapsed_clock_ticks_without_progress(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as d:
            app = tui.MediaRestoreApp(input_dir=Path(d))
            async with app.run_test():
                item = tui.MediaItem(
                    path=Path("/in/clip.mp4"), media_type="video",
                    output_path=Path("/out/clip.mp4"), status="active",
                )
                app._active_item = item
                app._job_start = time.time() - 3
                app._tick_active()
                detail = app.query_one("#job-detail")
                self.assertIn("running", str(detail.render()))


if __name__ == "__main__":
    unittest.main(verbosity=2)
