final class BeatDetector {

    private TimedQueue neighborLoudnesses;
    private float significanceThreshold;
    
    // Additions for visualization.
    float currentLoudness;
    float averageLoudness;
    float beatLoudness;
    
    BeatDetector(float retentionDuration, float threshold) {
        neighborLoudnesses = new TimedQueue(retentionDuration);
        significanceThreshold = threshold;
    }
    
    boolean processBuffer(AudioBuffer buffer) {
        currentLoudness = buffer.level();
        averageLoudness = average(neighborLoudnesses);
        beatLoudness = significanceThreshold * averageLoudness;

        neighborLoudnesses.add(currentLoudness);

        return currentLoudness >= beatLoudness;
    }

    private float average(TimedQueue queue) {
        List<Float> values = queue.getValues();
        float sum = 0;

        for (float value : values) {
            sum += value;
        }

        return sum / values.size();
    }
}
