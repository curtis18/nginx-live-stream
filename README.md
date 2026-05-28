# nginx-live-stream

Docker image for an nginx RTMP/HLS live streaming server with an HTML5 video.js player for monitoring broadcasts.

Built with:
- **nginx 1.30.2** (alpine 3.23) with [nginx-rtmp-module 1.2.2](https://github.com/arut/nginx-rtmp-module) compiled from source
- **[video.js 8](https://videojs.com/)** loaded via CDN with built-in HLS support

# How to use

## Run the container

```
docker run -p 80:80 -p 1935:1935 -d nginx-live-stream
```

## Stream to it

```
ffmpeg -re -i your-video.mp4 -c copy -f flv rtmp://localhost:1935/live/your-stream-key
```

Or use an encoder like [OBS](https://obsproject.com/) — set the server to `rtmp://localhost:1935/live` and enter any stream key.

## Watch

Open `http://localhost/` in your browser. The player will auto-detect the stream and start playback.

# Build from source

```
docker build -t nginx-live-stream .
```
