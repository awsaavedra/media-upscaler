# Local Open-Source Image and Video Upscaling Setup Guide

This guide covers fully local, free/open-source setup paths for image and video upscaling, organized by **easy**, **medium**, and **hard** setup complexity. The selected tools are all able to run on a local machine rather than relying on cloud processing.[web:13][web:78][web:9][web:2]

## Best fit for your hardware

A laptop with an 11th-gen Intel H-series CPU, 32 GB RAM, and an RTX 3050/3050 Ti/3060 is suitable for local image upscaling and workable for local video upscaling, with the RTX 3060 variant offering materially better throughput and more headroom than the 3050 class.[web:40][web:87][web:97][web:93]

## Complexity map

| Complexity | Tool | Category | Best for |
|---|---|---|---|
| Easy | Upscayl | Image | Fast local setup with GUI and batch jobs.[web:13][web:101] |
| Medium | Real-ESRGAN | Image / frame-based video | More control, scripting, and repeatable local pipelines.[web:80][web:9] |
| Hard | Chainner + HAT/DAT models | Image | Highest local control and access to stronger community models.[web:4] |
| Medium | Video2X | Video | End-to-end local video upscaling with model wrappers.[web:2][web:9] |
| Medium | Real-ESRGAN + FFmpeg | Video | Direct local frame pipeline with more manual control.[web:9] |
| Hard | Anime4K / Waifu2x workflows | Video | Best for anime/cartoon video or specialized local workflows.[web:8][web:83] |

## Easy setup: Upscayl for images

Upscayl is a free, open-source desktop application that runs locally and is commonly recommended as the easiest way to use AI image upscaling without dealing with command-line installation.[web:13][web:78][web:101]

### What this setup gives you

- Local-only processing, no cloud upload required.[web:13][web:78]
- Simple GUI for single images or folders.[web:101]
- Good default quality because it uses Real-ESRGAN-based models under the hood.[web:13][web:101]

### Install steps

1. Go to the official site or GitHub release page for Upscayl and download the build for your OS.[web:78][web:13]
2. Install the app normally.
3. Launch Upscayl.
4. In settings, select the GPU backend if the app exposes that option; on supported systems this helps ensure local GPU acceleration.[web:101]
5. Choose an input image or folder.
6. Select an upscale model and factor.
7. Pick an output folder on an SSD.
8. Run a small test batch first.

### Suggested starting settings

- Photos: start with 2x or 4x using the default general model.
- Low-quality web images: test more than one model because some will oversharpen.
- Batch jobs: place source and output folders on SSD storage to reduce I/O bottlenecks.[web:101][web:87]

### When to use this path

Use Upscayl when speed of setup matters more than deep control, and when the goal is to process still images locally with minimal friction.[web:13][web:101]

---

## Medium setup: Real-ESRGAN for images and frame-based video

Real-ESRGAN is the core open-source model behind many local upscalers and is a strong choice when more control is needed than a GUI provides.[web:80][web:9]

### What this setup gives you

- Full local execution with CLI-based repeatability.[web:80]
- Better automation for folders, scripts, and batch pipelines.[web:80][web:9]
- Reusable for both still images and videos after frame extraction.[web:9]

### Install steps

1. Install Git, Python, and FFmpeg if they are not already installed.
2. Download the official Real-ESRGAN repository or release build.[web:9]
3. Download the model weights recommended by the project.
4. Verify that NVIDIA drivers are installed and current.
5. Open a terminal in the Real-ESRGAN directory.
6. Run a single-image test first using the provided inference command from the project README.[web:80]
7. Confirm output quality and GPU use.

### Image workflow

1. Put source images in a dedicated folder.
2. Run Real-ESRGAN on one file first.
3. Adjust scale factor and model.
4. Run the full folder after validating the result.

### Video workflow

1. Use FFmpeg to extract frames from the source video.
2. Run Real-ESRGAN against the frame folder.[web:9]
3. Reassemble frames into video with FFmpeg.
4. Mux back the original audio if needed.

### Why this is medium complexity

This route is more powerful than Upscayl, but it requires terminal work, manual paths, and understanding frame extraction/reassembly for video.[web:80][web:9]

### When to use this path

Use Real-ESRGAN when batch automation, scripting, or frame-level control matters more than one-click convenience.[web:80][web:9]

---

## Hard setup: Chainner plus HAT/DAT models for images

Community discussions identify newer models such as HAT and DAT variants as some of the best open-source image upscaling options, especially when run through local graph-based tools like Chainner.[web:4]

### What this setup gives you

- Local node-based workflows for image enhancement.[web:4]
- Access to stronger community models than the default set found in simpler apps.[web:4]
- Fine-grained control over pre-processing, model choice, and output handling.

### Install steps

1. Download and install Chainner from its official releases.
2. Confirm CUDA/NVIDIA support is available if using GPU acceleration.
3. Download HAT or DAT model files from trusted community or project sources referenced by the model maintainers.[web:4]
4. Launch Chainner and create a simple graph: image input -> upscale model node -> image output.
5. Load one model at a time and test with a single image.
6. Save working graphs as presets for reuse.

### Suggested workflow

1. Start with a photo and an illustration as test assets.
2. Compare two models rather than trusting one default.
3. Use naming conventions for output folders so repeated tests stay organized.
4. Only scale up to 4x initially; larger jumps can hallucinate detail.

### Why this is hard

The complexity comes from model sourcing, node-graph setup, and the fact that results depend more on model/content matching than in a simple GUI app.[web:4]

### When to use this path

Use Chainner + HAT/DAT when maximum local control and experimentation matter, especially for mixed image types where one model does not fit everything.[web:4]

---

## Medium setup: Video2X for video upscaling

Video2X is one of the most commonly recommended open-source local video upscaling frameworks because it wraps models like Real-ESRGAN and Anime4K into a complete frame-to-video workflow.[web:2][web:9]

### What this setup gives you

- End-to-end local video workflow.[web:2][web:9]
- Integration with strong open-source backends such as Real-ESRGAN and Anime4K.[web:9]
- Better convenience for video than manually stitching your own frame pipeline.

### Install steps

1. Install FFmpeg first.
2. Download Video2X from its official repository or release page.[web:2]
3. Install any listed runtime dependencies.
4. Confirm the upscaler backend you want to use is enabled, such as Real-ESRGAN or Anime4K.[web:9]
5. Run a short test clip before attempting a long encode.

### Suggested workflow

1. Start with a 10- to 30-second clip.
2. Try 720p to 1080p before attempting 1080p to 4K.
3. Use SSD storage for temp directories because video pipelines create many intermediate files.[web:87]
4. Check audio sync after export.

### Why this is medium complexity

Video2X hides some complexity, but video upscaling still involves longer runtimes, temp storage planning, and backend selection.[web:2][web:87]

### When to use this path

Use Video2X when the priority is local video upscaling with a reasonably complete workflow and less manual FFmpeg handling.[web:2][web:9]

---

## Medium setup: Real-ESRGAN plus FFmpeg for video

This is the more manual version of video upscaling and is ideal when predictable scripting is more important than convenience.[web:9]

### Install steps

1. Install FFmpeg.
2. Install Real-ESRGAN.
3. Extract frames from a test video with FFmpeg.
4. Upscale frames with Real-ESRGAN.
5. Rebuild the video from frames with FFmpeg.
6. Add original audio back in as needed.

### Why people choose this path

- Easier to script and automate than some GUI tools.[web:80][web:9]
- Easier to inspect each stage if something goes wrong.
- Reproducible for repeated jobs with the same settings.

### Trade-offs

- More manual steps.
- More temp storage use.[web:87]
- Higher chance of user error in frame rate, naming, or muxing.

---

## Hard setup: Anime4K or Waifu2x-based local workflows for video

Anime4K and Waifu2x-based workflows are best suited to anime, line art, and stylized content rather than general live-action footage.[web:8][web:83]

### What this setup gives you

- Strong local performance for animation and cartoon material.[web:8][web:83]
- More specialized control over denoise and edge handling than general-purpose models.[web:83]

### Install steps

1. Choose Anime4K for speed and lighter real-time style workflows, or Waifu2x-based workflows for stronger denoise/upscale behavior on stylized content.[web:8][web:83]
2. Install the required app, wrapper, or script package.
3. Test on a short anime/cartoon clip first.
4. Tune denoise carefully; too much denoise can flatten line work.

### Why this is hard

The tools are specialized and may require more trial-and-error to match model, shader, or denoise settings to the source content.[web:8][web:83]

### When to use this path

Use this route only when the source is mostly anime, cartoon, or line-heavy stylized video.[web:8][web:83]

---

## Recommended starting path

For your hardware and desire to keep everything local, the lowest-friction path is:

1. **Images:** start with **Upscayl** for easy setup.[web:13][web:101]
2. **Images with more control:** move to **Real-ESRGAN**.[web:80]
3. **Images with highest control:** test **Chainner + HAT/DAT**.[web:4]
4. **Video:** start with **Video2X**.[web:2][web:9]
5. **Video with more manual control:** use **Real-ESRGAN + FFmpeg**.[web:9]
6. **Anime/cartoon video:** use **Anime4K or Waifu2x workflows**.[web:8][web:83]

## Storage and performance notes

Video upscaling creates large temporary frame folders, so free SSD space matters almost as much as GPU performance for smooth operation.[web:87] Local AI video upscaling is still time-intensive even on strong GPUs, so short validation runs before long encodes are the safest workflow.[web:40][web:91]

