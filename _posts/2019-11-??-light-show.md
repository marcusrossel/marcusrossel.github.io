---
title: "Simple Beat-Detection in Real-Time Audio"
---

< Intro >

Initially I had to write a sound-to-light converter for a [university project](https://github.com/marcusrossel/live-lightshow). It was supposed to output the light signals using an Arduino, so I used the Processing programming environment because it allows you to easily communicate with an Arduino.  
Hence, the following code will all be written in Processing - kind of a subset of Java. I'm not really a fan of the language, but the ends justify the means (for now).  
In Processing you are provided with a `setup` and a `draw`-method. The `setup`-method is called when the program launches and and the `draw`-method is repeatedly called for every frame of the program.

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

If we want to detect beats in an audio-stream, we will need to decide what we consider to be a *"beat"*. From this definition we can construct a series of heuristics that allow us to detect such a beat.

So first off - in vague terms - *a beat occurs when a specific point in an audio-stream is significantly louder than the surrounding audio*.  
This definition should feel rather intuitive, though you might already have scenarios in mind where this doesn't hold - we'll try to account for those cases later. If we try to translate this intuitive definition into our world of functions and buffers, we could say that *a beat occurs whenever an audio-buffer is significantly louder than its neighboring audio-buffers*. That still leaves *"significant"*, *"loud"* and *"neighboring"* undefined. We need to have precise definitions for these terms though, as the following example will demonstrate:

![Example](/Users/marcus/Desktop/Peaks.png)

This image shows the loudness (as defined later) of audio-buffers over time. Each vertical bar corresponds to the time that a buffer was recorded. So for example the peaks `1`, `2` and `3` are each bounded by two buffers of equal loudness, while `4` is bounded by two buffers of different loudness.  
Which of these buffers do you find suitable for a *"beat"*? Considering our previous definition, `1` to `4` could all be considered beats. Although you might intuitively rule out `4`, because it's not *"significantly"* louder than its preceding buffers, right? Also, `1` is still significantly louder than `2` and `3`, so maybe they're not beats either. But do we really consider `2` and `3` to be *"neighbors"* of `1`?

There are a variety of answers for these questions. Here are the one's we will use:
The *loudness* of an audio-buffer will be its [root mean square (RMS)](https://en.wikipedia.org/wiki/Root_mean_square), which is just a method for combining all of the samples in the buffer into one  value. We could also use a simple average, but apparently the RMS maps better to how we perceive loudness.  
The *neighbors* of an audio-buffer are the buffers that were captured during the last `N` seconds, where `N` will be adjustable.  
An audio-buffer has *significant loudness* if it is `L` percent louder than the average loudness of its neighbors - where `L` will be adjustable.

Using these more precise definitions we can start implementing a simple beat detector.

# < First Implementation >

Our beat detector will need to be updated regularly with new audio-buffers as they are captured, so we'll need a method for that (I'll explain its return type later):

```java
class BeatDetector {

    boolean processBuffer(AudioBuffer buffer) {
        // ...
    }
}
```

Also, if we want to be able to work with a buffer's neighbors we will need to capture them in some way. As we will see later, we only actually need the buffers' *loudness* values, not the entire buffers. And we also only need the values for the last `N` seconds (our definition of *"neighbors"*). To achieve this we'll use a time-bounded queue, which is just a queue that deletes elements that were added more than `N` seconds ago:

```java
class BeatDetector {

    private TimedQueue neighborLoudnesses;

    // ...
}
```

The implementation of the `TimedQueue` isn't actually important for the beat-detector, so I'll omit it here. If you're interested though, you can check out [this project's repository]().  

If we want to detect *"significant loudness"*, we need to get the average over the neighbors' loudnesses - so we'll need a method for that:

```java
class BeatDetector {

    // ...

    private float average(TimedQueue queue) {
        List<Float> values = queue.getValues();
        float sum = 0;

        for (float value : values) {
            sum += value
        }

        return sum / values.size();
    }
}
```

Also we need to define a percentage value for the *significant loudness*. This value will be passed in upon initialization, as will the time-bounded queue's value retention duration:

```java
class BeatDetector {

    // ...
    private float significanceThreshold;

    BeatDetector(float retentionDuration, float threshold) {
        neighborLoudnesses = new TimedQueue(retentionDuration);
        significanceThreshold = threshold;
    }

    // ...
}
```

The only thing missing now is the aforementioned method for turning an audio-buffer into a single loudness value - the *RMS*. Turns out the *minim* library has us covered again, with its `level`-method on `AudioBuffer`s - so we can just go ahead an write the actual algorithm for detecting a beat:


```java
class BeatDetector {

    // ...

    boolean processBuffer(AudioBuffer buffer) {
        float currentLoudness = buffer.level();
        float averageLoudness = average(neighborLoudnesses);
        float beatLoudness = significanceThreshold * averageLoudness;

        neighborLoudnesses.add(currentLoudness);

        return currentLoudness >= beatLoudness;
    }

    // ...
}
```

This method is relatively self-explanatory, but let's go over it anyway:
* get the current loudness
* get the average loudness over the last `N` seconds
* calculate the loudness required to trigger the detection of a *"beat"*
* add the current loudness to the set of neighbors, for next iteration
* return a value indicating whether the current audio-buffer triggered a beat, by comparing its loudness to the required *"beat-loudness"*

---

Now we can connect our beat-detector to the framework we constructed before:

```java
// ...
BeatDetector detector;

// ...

void setup() {
    // ...
    detector = new BeatDetector(/*retentionDuration*/ 5.0, /*threshold*/ 1.5);
}

void draw() {
    // ...
    boolean didDetectBeat = detector.processBuffer(buffer);

    if (didDetectBeat) {
        println("Beat");
    }
}
```

As you can see, we're going to define our neighborhood as being 5 seconds long and our significant loudness to be 150% of the average neighboring loudness.  
We then just check if there's a beat on every `draw`-cycle and print `"Beat"` if we find one.

You might notice that we haven't used the `fft` yet. If we take a look at how well our current algorithm works, we'll see why we need it for improvements.

# < Examples and Pitfalls >





In the next post we will add some more heuristics to fix some of these problems.  
Until then, thanks for reading!
