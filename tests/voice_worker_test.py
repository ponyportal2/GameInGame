"""No downloads, microphone access or provider calls in deterministic tests."""
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import time
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock
import wave

spec = importlib.util.spec_from_file_location("voice_worker", Path(__file__).resolve().parents[1] / "tools/voice/worker.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class RecognitionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.loads = []
        self.calls = []
        self.words = [" Make grenades", " red. "]
        self.fail = False

        def factory(model, **kwargs):
            self.loads.append((model, kwargs))
            def transcribe(path, **options):
                self.calls.append(options)
                def segments():
                    if self.fail:
                        raise RuntimeError("inference failed")
                    for text in self.words:
                        yield SimpleNamespace(text=text)
                return segments(), SimpleNamespace(language="en")
            return SimpleNamespace(transcribe=transcribe)
        self.engine = worker.Recognizer(self.root / "models", factory)

    def audio(self, name="clip.wav", silent=False, seconds=1):
        path = self.root / name
        with wave.open(str(path), "wb") as out:
            out.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
            out.writeframes(struct.pack("<h", 0 if silent else 2000) * int(16000 * seconds))
        return path

    def recognize(self, path=None, **options):
        return self.engine.transcribe(path or self.audio(), model="base", language="auto", **options)

    def test_real_worker_ipc_and_shutdown_without_model_download(self):
        session = self.root / "session"
        session.mkdir()
        audio = self.audio("session/silence.wav", silent=True)
        process = subprocess.Popen([sys.executable, str(Path(worker.__file__)), "--root", str(self.root),
                                    "--directory", str(session), "--parent", str(os.getpid())],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        worker.atomic_json(session / "request-ipc.json", {"id": "ipc", "audio": str(audio), "model": "base"})
        result = session / "result-ipc.json"
        deadline = time.monotonic() + 10
        while not result.exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(result.exists(), "actual worker should return a result")
        self.assertEqual(json.loads(result.read_text()), {"id": "ipc", "ok": True, "text": "", "language": ""})
        self.assertFalse(audio.exists())
        self.assertFalse((self.root / "models").exists(), "silence must not download any model")
        (session / "stop").touch()
        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, (stdout, stderr))

    def test_final_text_and_cached_cpu_model(self):
        self.assertEqual(self.recognize()["text"], "Make grenades red.")
        self.recognize()
        self.assertEqual(len(self.loads), 1)
        self.assertEqual(self.loads[0][1]["device"], "cpu")
        self.assertEqual(self.loads[0][1]["compute_type"], "int8")
        self.assertEqual(Path(self.loads[0][1]["download_root"]), self.root / "models")
        self.assertTrue(self.calls[0]["vad_filter"])
        self.assertIsNone(self.calls[0]["language"])

    def test_worker_exits_when_host_is_gone(self):
        session = self.root / "orphan"
        process = subprocess.Popen([sys.executable, str(Path(worker.__file__)), "--root", str(self.root),
                                    "--directory", str(session), "--parent", "0"],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(lambda: process.kill() if process.poll() is None else None)
        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, (stdout, stderr))

    def test_model_switch_and_language(self):
        self.recognize()
        self.engine.transcribe(self.audio(), model="tiny", language="ru")
        self.assertEqual([item[0] for item in self.loads], ["base", "tiny"])
        self.assertEqual(self.calls[-1]["language"], "ru")

    def test_silence_does_not_load_or_hallucinate(self):
        self.assertEqual(self.recognize(self.audio(silent=True))["text"], "")
        self.assertEqual(self.loads, [])

    def test_bad_model_and_long_audio_rejected_before_model_load(self):
        with self.assertRaises(ValueError):
            self.engine.transcribe(self.audio(), model="../../outside", language="auto")
        with self.assertRaises(ValueError):
            self.recognize(self.audio(seconds=61))
        self.assertEqual(self.loads, [])

    def test_generator_error_and_output_bound(self):
        self.fail = True
        with self.assertRaisesRegex(RuntimeError, "inference failed"):
            self.recognize()
        self.fail = False
        self.words = ["x" * 10000]
        with self.assertRaises(ValueError):
            self.recognize()

    def test_request_round_trip_and_cleanup(self):
        audio = self.audio()
        request = {"id": "roundtrip", "audio": str(audio), "model": "base", "language": "auto"}
        result = worker.handle_request(self.engine, self.root, request)
        self.assertEqual(result, {"id": "roundtrip", "ok": True, "text": "Make grenades red.", "language": "en"})
        self.assertFalse(audio.exists())
        worker.atomic_json(self.root / "result.json", result)
        self.assertEqual(json.loads((self.root / "result.json").read_text()), result)

    def test_error_cleanup_and_outside_audio_refusal(self):
        audio = self.audio()
        self.fail = True
        result = worker.handle_request(self.engine, self.root, {"id":"failed", "audio":str(audio), "model":"base", "language":"auto"})
        self.assertFalse(result["ok"])
        self.assertFalse(audio.exists())
        with tempfile.TemporaryDirectory() as outside:
            sentinel = Path(outside) / "keep.wav"
            sentinel.write_bytes(b"keep")
            result = worker.handle_request(self.engine, self.root, {"id":"escape", "audio":str(sentinel)})
            self.assertFalse(result["ok"])
            self.assertEqual(sentinel.read_bytes(), b"keep")


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.session = self.root / "sessions" / "install"
        self.session.mkdir(parents=True)
        self.environment = self.root / "environment"
        self.python = self.environment / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
        self.python.parent.mkdir(parents=True)
        self.python.write_text("old interpreter")
        self.model = self.root / "models" / "keep-model"
        self.model.parent.mkdir()
        self.model.write_text("cached weights")

    def create_environment(self, path, **kwargs):
        self.assertEqual(path, self.environment)
        self.python.write_text(sys.executable)

    def test_failed_install_retry_rebuilds_incomplete_environment_with_selected_python(self):
        failed = SimpleNamespace(poll=lambda: 1, returncode=1)
        succeeded = SimpleNamespace(poll=lambda: 0, returncode=0)
        with mock.patch.object(worker.venv, "create", side_effect=self.create_environment) as create, \
             mock.patch.object(worker.subprocess, "Popen", side_effect=[failed, succeeded]) as pip:
            with mock.patch.object(worker.sys, "executable", "selected-python-3.13"):
                worker.install(self.root, self.session, os.getpid())
            self.assertFalse(json.loads((self.session / "installed.json").read_text())["ok"])
            self.assertFalse((self.root / "installed.json").exists())
            with mock.patch.object(worker.sys, "executable", "selected-python-3.12"):
                worker.install(self.root, self.session, os.getpid())
            self.assertEqual(create.call_count, 2)
            create.assert_has_calls([mock.call(self.environment, with_pip=True, clear=True)] * 2)
            self.assertEqual(self.python.read_text(), "selected-python-3.12")
            self.assertEqual(pip.call_args.args[0][:4], [str(self.python), "-m", "pip", "install"])
            self.assertTrue(json.loads((self.session / "installed.json").read_text())["ok"])
            self.assertTrue((self.root / "installed.json").exists())
            self.assertEqual(self.model.read_text(), "cached weights")

    def test_successful_reinstall_rebuilds_with_new_selected_python(self):
        succeeded = SimpleNamespace(poll=lambda: 0, returncode=0)
        with mock.patch.object(worker.venv, "create", side_effect=self.create_environment) as create, \
             mock.patch.object(worker.subprocess, "Popen", return_value=succeeded) as pip:
            with mock.patch.object(worker.sys, "executable", "selected-python-A"):
                worker.install(self.root, self.session, os.getpid())
            self.assertTrue(json.loads((self.session / "installed.json").read_text())["ok"])
            self.assertTrue((self.root / "installed.json").exists())
            self.assertEqual(self.python.read_text(), "selected-python-A")
            with mock.patch.object(worker.sys, "executable", "selected-python-B"):
                worker.install(self.root, self.session, os.getpid())
            create.assert_has_calls([mock.call(self.environment, with_pip=True, clear=True)] * 2)
            self.assertEqual(create.call_count, 2)
            self.assertEqual(self.python.read_text(), "selected-python-B")
            self.assertEqual(pip.call_count, 2)
            self.assertEqual(pip.call_args.args[0][:4], [str(self.python), "-m", "pip", "install"])
            self.assertTrue(json.loads((self.session / "installed.json").read_text())["ok"])
            self.assertTrue((self.root / "installed.json").exists())
            self.assertEqual(self.model.read_text(), "cached weights")

    def test_failed_reinstall_invalidates_previous_success_marker(self):
        worker.atomic_json(self.root / "installed.json", {"packages": worker.PACKAGES})
        failed = SimpleNamespace(poll=lambda: 1, returncode=1)
        with mock.patch.object(worker.venv, "create") as create, \
             mock.patch.object(worker.subprocess, "Popen", return_value=failed):
            worker.install(self.root, self.session, os.getpid())
        create.assert_called_once_with(self.environment, with_pip=True, clear=True)
        self.assertFalse((self.root / "installed.json").exists())
        self.assertFalse(json.loads((self.session / "installed.json").read_text())["ok"])


if __name__ == "__main__":
    unittest.main()
