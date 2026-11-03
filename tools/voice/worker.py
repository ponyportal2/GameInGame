"""Local, persistent speech recognition. Models/environments live in user data.

Only this worker imports faster-whisper; the host never loads inference code.
File IPC carries one bounded WAV request at a time, never microphone audio to a
provider. Installation is explicit and does not modify global Python packages.
"""
import argparse
from array import array
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
import venv
import wave

MODELS = ("tiny", "base", "small", "medium", "large-v3", "turbo")
MAX_SECONDS = 60
MAX_TEXT = 4000
# 1.2.1 still uses av.open(metadata_errors=...), removed by PyAV 19.
# Keep the released engine usable without monkey-patching its decoder.
PACKAGES = ("faster-whisper==1.2.1", "av>=11,<19")


def atomic_json(path, value):
    path = Path(path)
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    os.replace(temp, path)


class Recognizer:
    def __init__(self, cache, factory=None):
        self.cache = str(cache)
        self.factory = factory
        self.model = None
        self.model_name = None

    def transcribe(self, audio, model="base", language="auto"):
        if model not in MODELS:
            raise ValueError("Unsupported Whisper model")
        if language not in ("auto", "en", "ru"):
            raise ValueError("Unsupported recognition language")
        with wave.open(str(audio), "rb") as wav:
            if wav.getsampwidth() != 2 or wav.getnchannels() not in (1, 2):
                raise ValueError("Expected mono/stereo 16-bit PCM WAV")
            duration = wav.getnframes() / wav.getframerate()
            if not 0.25 <= duration <= MAX_SECONDS + 0.1:
                raise ValueError("Record between 0.25 and 60 seconds")
            samples = array("h", wav.readframes(wav.getnframes()))
        if sys.byteorder != "little":
            samples.byteswap()
        if not samples or max(abs(v) for v in samples) < 32:
            return {"text": "", "language": ""}
        if self.model_name != model:
            if self.factory is None:
                from faster_whisper import WhisperModel
                self.factory = WhisperModel
            # CPU keeps recognition off the game's GPU; cap CPU contention too.
            self.model = None
            self.model_name = None
            self.model = self.factory(model, device="cpu", compute_type="int8",
                                      cpu_threads=min(4, max(1, (os.cpu_count() or 2) // 2)),
                                      download_root=self.cache)
            self.model_name = model
        segments, info = self.model.transcribe(str(audio), language=None if language == "auto" else language,
                                               beam_size=1, vad_filter=True, condition_on_previous_text=False)
        text = ""
        for segment in segments:
            text += segment.text
            if len(text) > MAX_TEXT:
                raise ValueError("Transcript too long; record a shorter message")
        return {"text": text.strip(), "language": info.language}


def handle_request(engine, directory, request):
    result = {"id": request.get("id", ""), "ok": False}
    audio = Path(request.get("audio", "")).resolve()
    owned = audio.parent == Path(directory).resolve() and audio.suffix == ".wav" and not audio.is_symlink()
    try:
        if not owned:
            raise ValueError("Recording must belong to this worker session")
        result.update(engine.transcribe(audio, request.get("model", "base"), request.get("language", "auto")))
        result["ok"] = True
    except Exception as error:
        result["error"] = str(error)[:1500]
    finally:
        if owned:
            audio.unlink(missing_ok=True)
    return result


def parent_alive(pid):
    if pid <= 0:
        return False
    if os.name == "nt":
        kernel = ctypes.windll.kernel32
        kernel.OpenProcess.restype = ctypes.c_void_p
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle:
            return False
        code = ctypes.c_ulong()
        try:
            return bool(kernel.GetExitCodeProcess(ctypes.c_void_p(handle), ctypes.byref(code))) and code.value == 259
        finally:
            kernel.CloseHandle(ctypes.c_void_p(handle))
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def install(root, directory, parent):
    """Explicit, isolated install; stop pip if the host disappears."""
    log = directory / "install.log"
    python = root / "environment" / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    try:
        if not python.exists():
            venv.create(root / "environment", with_pip=True)
        with log.open("w", encoding="utf-8") as output:
            process = subprocess.Popen([str(python), "-m", "pip", "install", "--disable-pip-version-check", *PACKAGES],
                                       stdout=output, stderr=subprocess.STDOUT,
                                       creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            deadline = time.monotonic() + 600
            while process.poll() is None:
                if not parent_alive(parent) or (directory / "stop").exists() or time.monotonic() > deadline:
                    process.kill()
                    process.wait()
                    raise RuntimeError("Voice installation cancelled or timed out")
                time.sleep(0.2)
        if process.returncode:
            raise RuntimeError("Installation failed. Choose a supported Python executable (3.11/3.12 recommended). " + log.read_text(encoding="utf-8", errors="replace")[-1000:])
        atomic_json(root / "installed.json", {"packages": PACKAGES})
        atomic_json(directory / "installed.json", {"ok": True})
    except Exception as error:
        atomic_json(directory / "installed.json", {"ok": False, "error": str(error)[:1500]})


def serve(root, directory, parent):
    # A daemon watcher still runs while native inference/model download blocks.
    def watch():
        while True:
            if not parent_alive(parent) or (directory / "stop").exists():
                os._exit(0)
            time.sleep(0.5)
    threading.Thread(target=watch, daemon=True).start()
    engine = Recognizer(root / "models")
    last = time.monotonic()
    while time.monotonic() - last < 300:
        for path in directory.glob("request-*.json"):
            request = json.loads(path.read_text(encoding="utf-8"))
            path.unlink()
            result = handle_request(engine, directory, request)
            atomic_json(directory / ("result-" + request["id"] + ".json"), result)
            last = time.monotonic()
        time.sleep(0.05)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--parent", type=int, required=True)
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    (install if args.install else serve)(args.root, args.directory, args.parent)


if __name__ == "__main__":
    main()
