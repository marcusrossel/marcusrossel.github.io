---
title: "Simple Beat Detection in Real-Time Audio - Part 1"
---

In this series of posts we will attempt to build some kind of algorithm that can be used to detect beats in real-time streams of audio - so basically without being able to look ahead.  
I had to write such an algorithm for a sound-to-light converter for a [university project](https://github.com/marcusrossel/live-lightshow). It was supposed to output the light signals using an Arduino, so I used the [Processing](https://processing.org) programming environment because it allows you to easily communicate with an Arduino.  
Hence, the following code will all be written in Processing - kind of a subset of Java. I'm not really a fan of the language, but   the ends justify the means (for now). And though I will explain the code in detail, the focus of this post shouldn't be the precise implementation but rather the concepts of the beat-detector.

# Processing Audio

In order to understand how the beat detection process works, we first need to figure out how to access the audio data and how to extract some basic information from it. Luckily there's a nice Processing-library for this called [minim](https://github.com/ddf/Minim). It implements the whole audio fetching part for us.  
Processing itself provides an overridable `setup` and a `draw` method. The `setup` method is called when the program launches and and the `draw` method is repeatedly called for every frame of the program. Using these tools, we can continuously fetch audio samples:

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

All we need to do is create an instance of `Mimim` to get access to the system's audio line-in (which you can select in your system settings). The `lineIn` will contain a new buffer of (usually 1024 or 2048) audio samples - called its `mix` - on every iteration of `draw`.

Assuming a frame rate of 30 frames per second, our `draw` method is called about every 33 milliseconds. So we also get a new audio buffer every 33 milliseconds. This would in turn mean that we get either 30720 (30 × 1024) or 61440 (30 × 2048) audio samples each second. Depending on the sampling rate used by *minim* we might actually be sampling at a different rate (like 44100Hz) though. So our buffers will generally have some missing or overlapping audio samples. This goes to show that our beat detector will not depend on single samples, but rather aggregates and trends of samples.

One example of this *"broad strokes"* analysis is the [Fourier transform](https://en.wikipedia.org/wiki/Fourier_transform). This transform is an admittedly very mathy function, but we can use it very practically.

> The Fourier transform (FT) decomposes a function of time (a signal) into its constituent frequencies.

So in our case: given a buffer of audio samples, we can figure out *which* sound frequencies made up those samples, as well as *how much* each of those frequencies contributed (how intense each frequency was).

To actually perform this Fourier transform, we can again fall back on the minim library. It provides something that can perform what is called a *"fast Fourier transform (FFT)"*:

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

# Definitions

If we want to detect beats in an audio stream, we will need to decide what we consider to be a *"beat"*. From this definition we can construct a series of heuristics that allow us to detect such a beat.

So first off, in vague terms:

> A beat occurs when a specific point in an audio stream is significantly louder than the surrounding audio.  

This definition should feel rather intuitive, though you might already have scenarios in mind where this doesn't hold - we'll try to account for those cases later. If we try to translate this intuitive definition into our world of functions and buffers, we could say that:

> A beat occurs whenever an audio buffer is significantly louder than its neighboring audio buffers.

That still leaves *"significant"*, *"loud"* and *"neighboring"* undefined. We need to have precise definitions for these terms though, as the following example will demonstrate:

![Example]({{ site.url }}/assets/beat-detector/images/part-1/Peaks.png)

This image shows the loudness (as defined later) of audio buffers over time. Each vertical bar corresponds to the time that a buffer was recorded. So for example the peaks `1`, `2` and `3` are each bounded by two buffers of equal loudness, while `4` is bounded by two buffers of different loudness.  
Which of these buffers do you find suitable for a *"beat"*? Considering our previous definition, `1` to `4` could all be considered beats. Although you might intuitively rule out `4`, because it's not *"significantly"* louder than its preceding buffers, right? Also, `1` is still significantly louder than `2` and `3`, so maybe they're not beats either. But do we really consider `2` and `3` to be *"neighbors"* of `1`?

There are a variety of answers for these questions. Here are the one's we will use:  
The *loudness* of an audio buffer will be its [root mean square (RMS)](https://en.wikipedia.org/wiki/Root_mean_square), which is just a method for combining all of the samples in the buffer into one  value. We could also use a simple average, but apparently the RMS maps better to how we perceive loudness.  
The *neighbors* of an audio buffer are the buffers that were captured during the last `N` seconds, where `N` will be adjustable.  
An audio buffer has *significant loudness* if it is `L` percent louder than the average loudness of its neighbors, where `L` will be adjustable.

Using these more precise definitions we can start implementing a simple beat detector.

# First Implementation

Our beat detector will need to be updated regularly with new audio buffers as they are captured, so we'll need a method for that (I'll explain its return type later):

```java
final class BeatDetector {

    boolean processBuffer(AudioBuffer buffer) {
        // ...
    }
}
```

Also, if we want to be able to work with a buffer's neighbors, we will need to capture them in some way. As we will see later, we only actually need the buffers' *loudness* values, not the entire buffers. And we also only need the values for the last `N` seconds (our definition of *"neighbors"*). To achieve this we'll use a time-bounded queue, which is just a queue that deletes elements that were added more than `N` seconds ago:

```java
final class BeatDetector {

    private TimedQueue neighborLoudnesses;

    // ...
}
```

The implementation of the `TimedQueue` isn't actually important for the beat detector, so I'll omit it here. If you're interested though, you can check out [this project's repository](https://github.com/marcusrossel/marcusrossel.github.io/tree/master/assets/beat-detector/code).  

If we want to detect *"significant loudness"*, we need to get the average over the neighbors' loudnesses - so we'll need a method for that:

```java
final class BeatDetector {

    // ...

    private float average(TimedQueue queue) {
        List<Float> values = queue.getValues();
        float sum = 0;

        for (float value : values) {
            sum += value;
        }

        return sum / values.size();
    }
}
```

We also need to define a percentage value for the *significant loudness*. This value will be passed in upon initialization, as will the time-bounded queue's value retention duration:

```java
final class BeatDetector {

    // ...
    private float significanceThreshold;

    BeatDetector(float retentionDuration, float threshold) {
        neighborLoudnesses = new TimedQueue(retentionDuration);
        significanceThreshold = threshold;
    }

    // ...
}
```

The only thing missing now is the aforementioned method for turning an audio buffer into a single loudness value - the *RMS*. Turns out the *minim* library has us covered again, with its `level` method on `AudioBuffer`s - so we can just go ahead an write the actual algorithm for detecting a beat:


```java
final class BeatDetector {

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
* return a value indicating whether the current audio buffer triggered a beat, by comparing its loudness to the required *"beat loudness"*

---

Now we can connect our beat-detector to the framework we constructed before:

```java
// ...
BeatDetector detector;

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

You might notice that we haven't used the `fft` yet. We'll use it in future posts to improve our detection algorithm. Because if we take a look at how well our current algorithm works, we'll see that there's a lot of room for improvements.

# Examples and Pitfalls

For the purposes of visualization I wrote a simple visualizer specifically for this beat detector. Like with `TimeQueue` the implementation is not important, so I won't post the code here.  
I'm routing my computer's audio output to a virtual input-device using a utility called [Soundflower](https://github.com/mattingalls/Soundflower) - if you're on Linux or Windows there exist easier ways to achieve this though.  

Let's test our detector by just running it on some music that has a clear beat. The following image shows a 10 second segment of [Jon Hopkins' Collider](https://www.google.com/search?&q=Jon+Hopkins+Collider):

![Collider]({{ site.url }}/assets/beat-detector/images/part-1/Collider.png)

 The white line is the loudness of the audio signal over time. The green and orange lines show the state of our detector. The way we've defined our beat detection criteria implies that we detect a beat anytime the white line is above the green line - i.e. our current loudness surpasses the beat detection threshold.

This might seem like desired behavior, but there's actually a slight problem with it. Take the peak labeled with `1` for example. It surpasses the threshold at some time T<sub>up</sub> and falls below it again at some time T<sub>down</sub>. During this entire time T<sub>1</sub> (= T<sub>down</sub> - T<sub>up</sub>) the `processBuffer` method will return `true`. This might not be a problem for short peaks like `1`, but what if T<sub>1</sub> would be 1 second long? The `processBuffer` method will probably be called several times over such a duration, returning `true` (i.e. *"yes, I've detected a beat"*) every time. If the users of the beat detector know this, it's an easy problem to solve. But we don't actually want them to have to deal with it, so we might as well build the solution into our detector.

The next thing apparent from the image above is that our threshold was not configured too well for this song. It's way too low, therefore detecting peaks (like `1`) that shouldn't trigger a beat. Ideally we would want it to be right below the peaks, like the red line.  
I will say right off the bat, that we won't manage to get as close to the peaks as the red line is, during the course of these posts. But we can achieve something closer to the quality of the blue line. And while that is definitely better than our current green threshold, it still has problems.

As you can tell, peaks `2`, `3` and `4` are actually split into two peaks that both pass the threshold. As humans we can understand quite intuitively that this does not mean that there were two beats - they're just way too close together. But we'll have to find some way to encode this in our algorithm as well.

So... while we now have a very basic implementation of a beat detector, there are many problems to fix. In the next post we will add some more heuristics to tackle some of them.  
Until then, thanks for reading!

<br/>

---

<br/>

A full code listing for this post can be found [here](https://github.com/marcusrossel/marcusrossel.github.io/tree/master/assets/beat-detector/code/Part1).
