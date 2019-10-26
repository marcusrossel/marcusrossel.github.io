---
title: "Detecting Beats in Real-Time Audio"
---

< Intro >

Initially I had to write a sound-to-light converter for a [university project](https://github.com/marcusrossel/live-lightshow). It was supposed to output the light signals using an Arduino, so I used the Processing programming environment because it allows you to easily communicate with an Arduino.  
Hence, the following code will all be written in Processing - kind of a subset of Java. I'm not really a fan of the language, but the ends justify the means (for now).  
In Processing you are provided with a `setup` and a `draw` method. The `setup` method is called when the program launches and and the `draw` method is repeatedly called for every frame of the program.

# < Basics >

In order to understand how the beat-detection process works, we first need to figure out how to access the audio data and how to extract some basic information from it.  
Luckily there's a nice Processing-library for this called [minim](https://github.com/ddf/Minim). It implements the whole audio-fetching part for us:

```java
import ddf.minim.*;

Minim minim;
AudioInput lineIn;

void setup() {
    minim = new Minim(this);
    lineIn = minim.getLineIn();
}

void draw() {
    AudioBuffer buffer = lineIn.mix;
}
```

All we need to do is create an instance of `Mimim` to get access to the system's audio line-in (which you can select in your system settings). The `lineIn` will contain a new buffer of (usually 1024 or 2048) audio-samples - called its `mix` - on every iteration of `draw`.

Assuming a framerate of 30 frames per second, that means we get a new buffer about every 33 milliseconds. Now this would in turn mean that we get either 30720 (30 × 1024) or 61440 (30 × 2048) audio-samples each second. The usual sampling rate is 44100Hz though. This implies that our buffers will generally have some missing or overlapping values. This goes to show that our beat-detector will not depend on single samples, but rather aggregates and trends of samples.

One example of this *"broad strokes"* analysis is the [Fourier transform](https://en.wikipedia.org/wiki/Fourier_transform). This transform is an admittedly very mathy function, but we can use it very practically.

> The Fourier transform (FT) decomposes a function of time (a signal) into its constituent frequencies.

So in our case: given a buffer of audio-samples, we can figure out *which* sound-frequencies made up those samples, as well as *how much* each of those frequencies contributed (how intense each frequency was).

To actually perform this Fourier transform, the minim library again comes to our rescue. It provides something that can perform what is called a *"fast Fourier transform (FFT)"*:

```java
// ...
import ddf.minim.analysis.*;

// ...
FFT fft;

void setup() {
    // ...
    fft = new FFT(lineIn.bufferSize(), lineIn.sampleRate());
}

void draw() {
    // ...
    fft.forward(buffer);
}
```

All we need to do is initialize the `fft` with the `lineIn`'s properties. Then for each new `buffer` we can decompose the audio samples into their collective frequencies using the `forward` method.

# < Analysis Method >

-> loudness  
-> frequency finder  
-> average over n seconds in frequency range  
-> deviation from average  
-> beat detection  
