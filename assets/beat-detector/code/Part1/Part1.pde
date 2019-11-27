import ddf.minim.*;
import ddf.minim.analysis.*;

Minim minim;
AudioInput lineIn;
FFT fft;
BeatDetector detector;
Visualizer visualizer;

void setup() {
    minim = new Minim(this);
    lineIn = minim.getLineIn();
    fft = new FFT(lineIn.bufferSize(), lineIn.sampleRate());
    detector = new BeatDetector(/*retentionDuration*/ 5.0, /*threshold*/ 1.5);
    
    // Additions for visualization.
    visualizer = new Visualizer();
    size(1080, 720);
    surface.setResizable(true);
}

void draw() {
    AudioBuffer buffer = lineIn.mix;
    fft.forward(buffer);
    
    boolean didDetectBeat = detector.processBuffer(buffer);

    if (didDetectBeat) {
        println("Beat");
    }
    
    visualizer.update(fft, didDetectBeat);
}
