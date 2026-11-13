#!/usr/bin/env python3
"""libretro コアを ctypes で直接叩く最小フロントエンド (画面・音なしで ROM を回す)。

  emu = Emu("build/cradle-edge.sfc")          # 既定は snes9x
  emu.run(60)                                  # 60 フレーム進める
  emu.run(10, "Y")                             # Y を押したまま 10 フレーム
  emu.screenshot("out.png")
  emu.ram[0x10]                                # WRAM を読む
"""
import ctypes as C
import os

from PIL import Image

CORES = {
    "snes9x": "/usr/lib/x86_64-linux-gnu/libretro/snes9x_libretro.so",
    "bsnes": "/usr/lib/x86_64-linux-gnu/libretro/bsnes_mercury_accuracy_libretro.so",
}
BUTTONS = {"B": 0, "Y": 1, "SELECT": 2, "START": 3, "UP": 4, "DOWN": 5, "LEFT": 6, "RIGHT": 7,
           "A": 8, "X": 9, "L": 10, "R": 11}


class GameInfo(C.Structure):
    _fields_ = [("path", C.c_char_p), ("data", C.c_void_p), ("size", C.c_size_t),
                ("meta", C.c_char_p)]


ENV_CB = C.CFUNCTYPE(C.c_bool, C.c_uint, C.c_void_p)
VIDEO_CB = C.CFUNCTYPE(None, C.c_void_p, C.c_uint, C.c_uint, C.c_size_t)
AUDIO_CB = C.CFUNCTYPE(None, C.c_int16, C.c_int16)
AUDIO_BATCH_CB = C.CFUNCTYPE(C.c_size_t, C.c_void_p, C.c_size_t)
POLL_CB = C.CFUNCTYPE(None)
STATE_CB = C.CFUNCTYPE(C.c_int16, C.c_uint, C.c_uint, C.c_uint, C.c_uint)


class Emu:
    def __init__(self, rom_path, core="snes9x"):
        self.core = C.CDLL(CORES.get(core, core))
        self.pixfmt = 0
        self.frame = None
        self.held = set()
        self.frames = 0
        self.audio = bytearray()   # 16bit ステレオ
        self._dir = C.create_string_buffer(os.path.abspath("build").encode())

        def env(cmd, data):
            if cmd == 10:  # SET_PIXEL_FORMAT
                self.pixfmt = C.cast(data, C.POINTER(C.c_int))[0]
                return True
            if cmd in (9, 31):  # SYSTEM / SAVE ディレクトリ
                C.cast(data, C.POINTER(C.c_char_p))[0] = C.cast(self._dir, C.c_char_p)
                return True
            return False

        def video(data, w, h, pitch):
            if data:
                self.frame = (C.string_at(data, pitch * h), w, h, pitch)

        def audio(data, frames):
            self.audio += C.string_at(data, frames * 4)
            return frames

        def state(port, device, index, bid):
            if port != 0 or device != 1:
                return 0
            return 1 if bid in self.held else 0

        self._cbs = (ENV_CB(env), VIDEO_CB(video), AUDIO_CB(lambda l, r: None),
                     AUDIO_BATCH_CB(audio), POLL_CB(lambda: None), STATE_CB(state))
        c = self.core
        c.retro_set_environment(self._cbs[0])
        c.retro_init()
        c.retro_set_video_refresh(self._cbs[1])
        c.retro_set_audio_sample(self._cbs[2])
        c.retro_set_audio_sample_batch(self._cbs[3])
        c.retro_set_input_poll(self._cbs[4])
        c.retro_set_input_state(self._cbs[5])
        self._rom = open(rom_path, "rb").read()
        info = GameInfo(rom_path.encode(), C.cast(C.c_char_p(self._rom), C.c_void_p),
                        len(self._rom), None)
        c.retro_load_game.argtypes = [C.POINTER(GameInfo)]
        c.retro_load_game.restype = C.c_bool
        if not c.retro_load_game(C.byref(info)):
            raise RuntimeError("ROM を読み込めません")
        c.retro_get_memory_data.restype = C.c_void_p
        c.retro_get_memory_data.argtypes = [C.c_uint]
        c.retro_get_memory_size.restype = C.c_size_t
        c.retro_get_memory_size.argtypes = [C.c_uint]
        size = c.retro_get_memory_size(2)
        self.ram = (C.c_uint8 * size).from_address(c.retro_get_memory_data(2))
        ssize = c.retro_get_memory_size(0)   # バッテリーバックアップ
        self.sram = (C.c_uint8 * ssize).from_address(c.retro_get_memory_data(0)) if ssize else None

    def run(self, n=1, buttons=""):
        self.held = {BUTTONS[b] for b in buttons.replace("+", " ").split()}
        for _ in range(n):
            self.core.retro_run()
            self.frames += 1
        self.held = set()

    def save_state(self):
        c = self.core
        c.retro_serialize_size.restype = C.c_size_t
        n = c.retro_serialize_size()
        buf = C.create_string_buffer(n)
        c.retro_serialize.argtypes = [C.c_void_p, C.c_size_t]
        c.retro_serialize.restype = C.c_bool
        assert c.retro_serialize(buf, n)
        return buf.raw

    def load_state(self, data):
        c = self.core
        c.retro_unserialize.argtypes = [C.c_void_p, C.c_size_t]
        c.retro_unserialize.restype = C.c_bool
        buf = C.create_string_buffer(data, len(data))
        assert c.retro_unserialize(buf, len(data))

    def audio_peak(self, clear=True):
        """溜まった音声の最大振幅 (0-32767)。"""
        import array
        a = array.array("h", bytes(self.audio[:len(self.audio) // 2 * 2]))
        if clear:
            self.audio = bytearray()
        return max((abs(v) for v in a), default=0)

    def word(self, addr):
        return self.ram[addr] | (self.ram[addr + 1] << 8)

    def image(self):
        data, w, h, pitch = self.frame
        if self.pixfmt == 1 or (self.pixfmt == 0 and pitch >= w * 4):  # XRGB8888 (bsnes は形式を知らせずに使う)
            img = Image.frombuffer("RGBA", (w, h), data, "raw", "BGRA", pitch, 1).convert("RGB")
        else:  # RGB565 / 0RGB1555
            mode = "BGR;16" if self.pixfmt == 2 else "BGR;15"
            img = Image.frombuffer("RGB", (w, h), data, "raw", mode, pitch, 1)
        if w == 512:                             # 横 2 倍で出すコアは 256 に戻す
            img = img.resize((256, h), Image.NEAREST)
        return img

    def screenshot(self, path, scale=2):
        img = self.image()
        if scale != 1:
            img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
        img.save(path)
        return path
