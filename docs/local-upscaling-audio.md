# Local Audio Upscaling Setup Guide

> Research archive — audio tool survey for planned v4. Nothing implemented yet; reference only.

This is a starter guide for trying **local**, **open-source** audio upscaling or enhancement tools on your own machine. These are not as mature as image/video upscalers, but there are a few credible projects worth testing locally before paying for commercial software.

## What to try first

| Tool | Best use | Difficulty | Exact project |
|---|---|---:|---|
| AudioSR | True audio super-resolution / bandwidth extension to 48 kHz | Medium | [haoheliu/versatile_audio_super_resolution](https://github.com/haoheliu/versatile_audio_super_resolution)  |
| OpenVINO Audacity plugin | Easier GUI workflow inside Audacity with Audio Super Resolution effect | Easy | [intel/openvino-plugins-ai-audacity](https://github.com/intel/openvino-plugins-ai-audacity)  |
| DeepFilterNet | Noise suppression and cleanup, not true SR, but useful in a restoration chain | Medium | [Rikorose/DeepFilterNet](https://github.com/Rikorose/DeepFilterNet)  |

## 1) Easy: Audacity + OpenVINO AI plugins

This is the easiest local starting point because it gives a GUI workflow inside Audacity instead of requiring direct model scripting. Intel's OpenVINO Audacity plugin includes **Audio Super Resolution** and explicitly notes that the feature is a port of AudioSR.

### Exact project links

- Plugin repo: [intel/openvino-plugins-ai-audacity](https://github.com/intel/openvino-plugins-ai-audacity)
- Audacity OpenVINO page referenced by Intel: [audacityteam.org/download/openvino](https://www.audacityteam.org/download/openvino/)
- Underlying SR project used by the plugin: [haoheliu/versatile_audio_super_resolution](https://github.com/haoheliu/versatile_audio_super_resolution)

### What it does

- Adds AI effects inside Audacity.
- Lets you run Audio Super Resolution locally on CPU, GPU, or NPU depending on the device and plugin support shown in Intel's demo.
- Best for users who want to test audio upscaling without building a command-line pipeline.

### Setup steps

1. Install Audacity 3.7.1 or newer.
2. Download the latest OpenVINO Audacity plugin release from GitHub.
3. During installation, point the installer at the correct Audacity install path if you have multiple versions installed.
4. Open Audacity.
5. Load a test audio file.
6. Select the audio region.
7. Go to **Effects** -> **OpenVINO Effects** -> **Super Resolution**.
8. Start with default settings and export a short test result.

### When to use it

Use this if the priority is the fastest path to trying local audio upscaling with the least setup friction.

---

## 2) Medium: AudioSR direct from GitHub

AudioSR is the main open-source project focused on true **audio super-resolution**. The project describes itself as "Versatile audio super resolution (any -> 48kHz)" and supports music, speech, and other sound types.

### Exact project links

- Main GitHub repo: [haoheliu/versatile_audio_super_resolution](https://github.com/haoheliu/versatile_audio_super_resolution)
- Project page: [audioldm.github.io/audiosr](https://audioldm.github.io/audiosr/)
- Optional ComfyUI wrapper: [Saganaki22/ComfyUI-AudioSR](https://github.com/Saganaki22/ComfyUI-AudioSR)

### What it does

- Upscales low-bandwidth audio to high-resolution 48 kHz output.
- Works on music, speech, sound effects, and environmental audio according to the project page.
- Can be run from the command line or with a local Gradio demo.

### Setup steps

1. Install Python 3.9 in a fresh virtual environment or Conda environment.
2. Clone the repo:
   ```bash
   git clone https://github.com/haoheliu/versatile_audio_super_resolution.git
   cd versatile_audio_super_resolution
   ```
3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
   The repo also documents package installation via `pip install audiosr==0.0.7` or direct Git install.
4. For a local GUI demo, run:
   ```bash
   python app.py
   ```
   Then open the displayed local URL in your browser.
5. For CLI inference on one file, run:
   ```bash
   audiosr -i path/to/input.wav
   ```
   The project states output is saved to `./output` by default.
6. Test on a short clip first before processing long files.

### Optional alternate local CLI path

A community fork documents a more explicit local inference flow and example parameters if the main repo flow gives trouble.

- Fork: [jarredou/AudioSR-Colab-Fork](https://github.com/jarredou/AudioSR-Colab-Fork)

### When to use it

Use AudioSR when the goal is actual **bandwidth extension / super-resolution**, not just noise cleanup.

---

## 3) Medium: DeepFilterNet as a cleanup companion

DeepFilterNet is **not** true audio super-resolution, but it is a strong open-source local tool for noise suppression and can be useful before or after AudioSR in a restoration workflow.

### Exact project links

- Main GitHub repo: [Rikorose/DeepFilterNet](https://github.com/Rikorose/DeepFilterNet)
- OpenVINO model card referencing the same project: [Intel/deepfilternet-openvino](https://huggingface.co/Intel/deepfilternet-openvino)

### What it does

- Suppresses background noise in noisy WAV files using deep filtering.
- Offers a precompiled binary according to the GitHub repo, which makes it easier to test locally than some research-only tools.
- Works well as part of a chain: clean audio first, then try super-resolution if needed.

### Setup steps

1. Go to the DeepFilterNet GitHub repository releases or README.
2. Download the precompiled binary if available for your platform, or follow the Python/Rust build instructions from the repo.
3. Run a first cleanup pass on a noisy WAV file.
4. Compare the cleaned file against the original before attempting AudioSR.
5. If the file still lacks high-frequency detail, feed the cleaned file into AudioSR as the next stage.

### When to use it

Use this when your real problem is noisy or muddy audio rather than missing high-frequency bandwidth.

---

## Suggested starting order

For the fastest local starting point:

1. **Try Audacity + OpenVINO plugin first** if you want a GUI and the lowest setup friction.
2. **Try AudioSR second** if you want the most direct open-source audio super-resolution project.
3. **Add DeepFilterNet third** if the source audio is noisy and needs cleanup before enhancement.

## Practical expectations

Audio upscaling is still less mature than image or video upscaling. AudioSR is the main project worth trying for true super-resolution, while the OpenVINO Audacity plugin is the easiest way to test it locally in a GUI, and DeepFilterNet is best treated as a companion restoration tool rather than a direct upscaler.

