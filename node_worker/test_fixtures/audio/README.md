# Audio pipeline fixtures

These deterministic 0.4-second fixtures keep the muxer tests small and offline:

- `video-only.mp4`: H.264 video with no audio track.
- `audio-only.m4a`: AAC-LC audio with no video track.
- `embedded-audio.mp4`: H.264 video with an AAC-LC audio track.

They were generated with FFmpeg 8.1:

```sh
ffmpeg -f lavfi -i color=c=black:s=32x32:r=5:d=0.4 -an \
  -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
  -movflags +faststart video-only.mp4

ffmpeg -f lavfi -i sine=frequency=440:sample_rate=44100:duration=0.4 -vn \
  -c:a aac -b:a 32k -movflags +faststart audio-only.m4a

ffmpeg -f lavfi -i color=c=black:s=32x32:r=5:d=0.4 \
  -f lavfi -i sine=frequency=440:sample_rate=44100:duration=0.4 \
  -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p \
  -c:a aac -b:a 32k -shortest -movflags +faststart embedded-audio.mp4
```
